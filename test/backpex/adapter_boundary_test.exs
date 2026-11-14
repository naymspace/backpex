defmodule Backpex.AdapterBoundaryTest do
  @moduledoc """
  Backpex is Ecto-first, but only its adapters may build queries, call a repo or inspect schemas. Everything else uses
  the `Backpex.Adapter` callbacks, see `Backpex.Resource`. Forms may still use `Ecto.Changeset`.
  """
  use ExUnit.Case, async: true

  @adapter_paths ["lib/backpex/adapters/", "lib/backpex/preferences/adapters/"]

  @schema_keys [:__schema__, :__struct__, :__meta__, :__changeset__]

  @template_violation ~r/\b(adapter_config|__schema__|__struct__)\b|\bEcto\.(?!Changeset)|\bPostgrex\b|\bBackpex\.Adapters\.|\brepo\./

  test "only adapters build queries, call a repo or inspect schemas" do
    violations =
      for path <- Path.wildcard("lib/**/*.{ex,heex}"),
          not String.starts_with?(path, @adapter_paths),
          violation <- violations(File.read!(path), path),
          do: violation

    assert violations == []
  end

  test "the behaviour declares validate_config!/1, which every LiveResource calls on its adapter" do
    assert {:validate_config!, 1} in Backpex.Adapter.behaviour_info(:callbacks)
    refute {:validate_config!, 1} in Backpex.Adapter.behaviour_info(:optional_callbacks)
  end

  test "finds the violations of a module" do
    source = ~S'''
    defmodule Violations do
      @moduledoc "Docs may mention Ecto.Query, repo.all/1 and __schema__/2."
      @callback query(Ecto.Query.t()) :: Ecto.Query.t()

      import Ecto.Query
      alias Backpex.Adapters.Ecto, as: EctoAdapter

      @default_adapter Backpex.Adapters.Ecto

      def violations(live_resource, error) do
        schema = live_resource.adapter_config(:schema)
        schema.__schema__(:association, :user)
        live_resource.adapter_config(:repo).all(schema)
        repo = live_resource.adapter_config(:repo)
        repo.all(schema)
        Ecto.Type.cast(:id, "1")
        EctoAdapter.list_query([], [], %{}, live_resource)
        match?(%Postgrex.Error{}, error)
        Ecto.Changeset.change(schema.__struct__())
        ~H"<p>{@live_resource.adapter_config(:schema)}</p>"
        is_struct(error, Ecto.Association.NotLoaded) or live_resource.config(:adapter) == Backpex.Adapters.Ecto
        function_exported?(schema, :__schema__, 1) and apply(schema, :__schema__, [:fields])
        match?(%{__struct__: _schema, __meta__: _meta}, error)
        live_resource.config.repo.all(schema)
        other_repo = repo
        other_repo.all(Ecto.Changeset.apply_changes(error))
      end
    end
    '''

    assert source |> violations("lib/violations.ex") |> Enum.map(&String.replace_prefix(&1, "lib/violations.ex:", "")) ==
             [
               "5: uses Ecto.Query",
               "6: uses Backpex.Adapters.Ecto",
               "11: reads the adapter config",
               "12: inspects a schema with __schema__",
               "13: reads the adapter config",
               "14: reads the adapter config",
               "15: calls a repo",
               "16: uses Ecto.Type",
               "18: uses Postgrex.Error",
               "19: inspects a schema with __struct__",
               "20: mentions adapter_config in a template",
               "21: uses Backpex.Adapters.Ecto",
               "21: uses Ecto.Association.NotLoaded",
               "22: inspects a schema with __schema__",
               "22: inspects a schema with __schema__",
               "23: inspects a schema with __meta__",
               "23: inspects a schema with __struct__",
               "24: calls a repo",
               "26: calls a repo"
             ]
  end

  defp violations(source, path) do
    if String.ends_with?(path, ".heex") do
      source
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {line_source, line} -> template_violations(line_source, path, line) end)
    else
      source
      |> Code.string_to_quoted!(file: path)
      |> Macro.prewalk([], fn
        # Module attributes hold docs and typespecs.
        {:@, _meta, _args}, violations -> {nil, violations}
        node, violations -> {node, node_violations(node) ++ violations}
      end)
      |> elem(1)
      |> Enum.sort()
      |> Enum.map(fn {line, message} -> "#{path}:#{line}: #{message}" end)
    end
  end

  defp node_violations({:sigil_H, meta, [{:<<>>, _meta, [template]}, _modifiers]}) when is_binary(template) do
    template
    |> template_violations(nil, meta[:line])
    |> Enum.map(&{meta[:line], &1})
  end

  # A module wherever it is named: in a directive, a struct, a call or as a value, e.g. `is_struct(item, Ecto.Schema)`.
  defp node_violations({:__aliases__, meta, parts}), do: module_violations(parts, meta)

  # The keys of a schema in a map, e.g. the pattern `%{__struct__: schema}`.
  defp node_violations({:%{}, meta, pairs}) when is_list(pairs) do
    for {key, _value} <- pairs, key in @schema_keys, do: {meta[:line], "inspects a schema with #{key}"}
  end

  defp node_violations({{:., meta, [receiver, function]}, _call_meta, args}) when is_atom(function) do
    cond do
      function in @schema_keys -> [{meta[:line], "inspects a schema with #{function}"}]
      function == :adapter_config -> [{meta[:line], "reads the adapter config"}]
      repo?(receiver) -> [{meta[:line], "calls a repo"}]
      true -> argument_violations(args, meta)
    end
  end

  defp node_violations({function, meta, args}) when is_atom(function) and function != :. and is_list(args),
    do: argument_violations(args, meta)

  defp node_violations(_node), do: []

  # The name of a function of a schema as an argument, e.g. `function_exported?(schema, :__schema__, 1)`.
  defp argument_violations(args, meta) do
    for arg <- args, arg in @schema_keys, do: {meta[:line], "inspects a schema with #{arg}"}
  end

  defp module_violations(parts, meta) do
    if forbidden_module?(parts), do: [{meta[:line], "uses #{Enum.join(parts, ".")}"}], else: []
  end

  defp forbidden_module?([:Ecto, :Changeset | _rest]), do: false
  defp forbidden_module?([:Ecto | _rest]), do: true
  defp forbidden_module?([:Postgrex | _rest]), do: true
  defp forbidden_module?([:Backpex, :Adapters | _rest]), do: true
  defp forbidden_module?(_parts), do: false

  # A variable or a field named `repo` or `..._repo`, e.g. `config.repo`, or a module named `Repo`.
  defp repo?({name, _meta, context}) when is_atom(name) and is_atom(context), do: repo_name?(name)
  defp repo?({{:., _meta, [_receiver, name]}, _call_meta, []}) when is_atom(name), do: repo_name?(name)
  defp repo?({:__aliases__, _meta, parts}), do: List.last(parts) == :Repo
  defp repo?(_receiver), do: false

  defp repo_name?(name), do: name == :repo or name |> Atom.to_string() |> String.ends_with?("_repo")

  defp template_violations(template, path, line) do
    @template_violation
    |> Regex.scan(template)
    |> Enum.map(fn [match | _groups] ->
      message = "mentions #{String.trim_trailing(match, ".")} in a template"
      if path, do: "#{path}:#{line}: #{message}", else: message
    end)
  end
end
