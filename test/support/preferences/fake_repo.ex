defmodule Backpex.Test.Preferences.FakeRepo do
  @moduledoc """
  Minimal `Ecto.Repo` stand-in for `Backpex.Preferences.Adapters.Ecto` tests.

  Rows live in the calling process keyed by `{scope_values, key}`, mirroring a
  unique index over `scope_fields ++ [:key]`. Query parameters are inspected so
  tests fail when the adapter omits part of the scope.
  """

  @key :backpex_fake_repo_rows

  @doc "Every `{key, envelope}` stored for the ordered scope values."
  def rows_for(scope_values) when is_list(scope_values) do
    for {{row_scope, key}, envelope} <- rows(), row_scope == scope_values, do: {key, envelope}
  end

  def one(query) do
    params = params(query)
    {scope_values, [key]} = Enum.split(params, -1)

    Map.get(rows(), {scope_values, key})
  end

  def all(query) do
    params = params(query)
    {scope_values, [pattern]} = Enum.split(params, -1)
    regex = like_to_regex(pattern)

    for {{row_scope, key}, envelope} <- rows(),
        row_scope == scope_values,
        Regex.match?(regex, key),
        do: {key, envelope}
  end

  # `Ecto.Repo.insert!/2` takes a struct or a changeset; mirror that.
  def insert!(insertable, opts) do
    conflict_target = Keyword.fetch!(opts, :conflict_target)
    {scope_fields, [:key]} = Enum.split(conflict_target, -1)
    row = apply_changes(insertable)
    scope_values = Enum.map(scope_fields, &Map.fetch!(row, &1))

    Process.put(@key, Map.put(rows(), {scope_values, row.key}, row.value))
    row
  end

  defp apply_changes(%Ecto.Changeset{} = changeset), do: Ecto.Changeset.apply_changes(changeset)
  defp apply_changes(struct), do: struct

  # Values bound into the query's `where` clauses, in order.
  defp params(%Ecto.Query{wheres: wheres}) do
    Enum.flat_map(wheres, fn %{params: params} -> Enum.map(params, &elem(&1, 0)) end)
  end

  defp like_to_regex(pattern) do
    source =
      pattern
      |> String.split(~r/[%_]/, include_captures: true)
      |> Enum.map_join(fn
        "%" -> ".*"
        "_" -> "."
        literal -> Regex.escape(literal)
      end)

    Regex.compile!("^" <> source <> "$")
  end

  defp rows, do: Process.get(@key, %{})
end
