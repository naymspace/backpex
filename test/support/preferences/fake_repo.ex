defmodule Backpex.Test.Preferences.FakeRepo do
  @moduledoc """
  Minimal `Ecto.Repo` stand-in for `Backpex.Preferences.Adapters.Ecto` tests.

  Backpex's test suite has no database, but the adapter is still worth testing
  without one: what matters is that it scopes by identity, looks rows up by
  key, wraps values in the storage envelope, and rebuilds the nested subtree
  `c:Backpex.Preferences.Adapter.get_map/3` must return.

  Rows live in the calling process keyed by `{identity, key}`, mirroring the
  unique index the real table carries.

  `all/1` and `one/1` read the bound parameters off the `Ecto.Query` rather
  than ignoring it, so a query that forgets to scope by identity or filters on
  the wrong column fails the test. `all/1` reproduces SQL `LIKE` semantics
  including `_` as a single-character wildcard — that over-match is real, and
  rejecting it is `Backpex.Preferences.Adapter.nest/2`'s job, not the query's.
  """

  @key :backpex_fake_repo_rows

  @doc "Seeds a row in the shape the adapter writes."
  def put_row(identity, key, envelope) do
    Process.put(@key, Map.put(rows(), {identity, key}, envelope))
    :ok
  end

  @doc "Every `{key, envelope}` stored for `identity`, for assertions."
  def rows_for(identity) do
    for {{row_identity, key}, envelope} <- rows(), row_identity == identity, do: {key, envelope}
  end

  def one(query) do
    [identity, key] = params(query)

    Map.get(rows(), {identity, key})
  end

  def all(query) do
    [identity, pattern] = params(query)
    regex = like_to_regex(pattern)

    for {{row_identity, key}, envelope} <- rows(),
        row_identity == identity,
        Regex.match?(regex, key),
        do: {key, envelope}
  end

  # `Ecto.Repo.insert!/2` takes a struct or a changeset; mirror that.
  def insert!(insertable, opts) do
    [identity_field, :key] = Keyword.fetch!(opts, :conflict_target)
    row = apply_changes(insertable)

    put_row(Map.fetch!(row, identity_field), row.key, row.value)
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
