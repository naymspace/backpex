defmodule Backpex.AdapterBoundaryTest do
  @moduledoc """
  Backpex is Ecto-first, but only its adapters may build queries, call a repo or inspect schemas. Everything else uses
  the `Backpex.Adapter` callbacks, see `Backpex.Resource`. Forms may still use `Ecto.Changeset`.
  """
  use ExUnit.Case, async: true

  @adapter_paths ["lib/backpex/adapters/", "lib/backpex/preferences/adapters/"]

  # The query callbacks of filters and metrics belong to `Backpex.Adapters.Ecto`, which calls them with an Ecto query
  # and its repo. `BackpexWeb` imports `Ecto.Query` for them.
  @query_callback_paths ["lib/backpex_web.ex", "lib/backpex/filters/", "lib/backpex/metrics/"]

  @template_violation ~r/\b(adapter_config|__schema__|__struct__)\b|\bEcto\.(?!Changeset)|\bPostgrex\b|\bBackpex\.Adapters\.|\brepo\./

  test "only adapters build queries, call a repo or inspect schemas" do
    violations =
      for path <- Path.wildcard("lib/**/*.{ex,heex}"),
          not String.starts_with?(path, @adapter_paths),
          violation <- violations(File.read!(path), path),
          do: violation

    assert violations == []
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
               "20: mentions adapter_config in a template"
             ]

    assert violations("import Ecto.Query\nrepo.one(query)", "lib/backpex/metrics/sum.ex") == []
  end

  defp violations(source, path) do
    if String.ends_with?(path, ".heex") do
      source
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {line_source, line} -> template_violations(line_source, path, line) end)
    else
      exceptions = if String.starts_with?(path, @query_callback_paths), do: [:query, :repo], else: []

      source
      |> Code.string_to_quoted!(file: path)
      |> Macro.prewalk([], fn
        # Module attributes hold docs and typespecs.
        {:@, _meta, _args}, violations -> {nil, violations}
        node, violations -> {node, node_violations(node, path, exceptions) ++ violations}
      end)
      |> elem(1)
      |> Enum.sort_by(fn {line, _message} -> line end)
      |> Enum.map(fn {line, message} -> "#{path}:#{line}: #{message}" end)
    end
  end

  defp node_violations({:sigil_H, meta, [{:<<>>, _meta, [template]}, _modifiers]}, _path, _exceptions)
       when is_binary(template) do
    template
    |> template_violations(nil, meta[:line])
    |> Enum.map(&{meta[:line], &1})
  end

  defp node_violations({directive, meta, [{:__aliases__, _meta, parts} | _rest]}, _path, exceptions)
       when directive in [:import, :alias, :require, :use] do
    module_violations(parts, meta, exceptions)
  end

  defp node_violations({:%, meta, [{:__aliases__, _meta, parts}, _fields]}, _path, exceptions) do
    module_violations(parts, meta, exceptions)
  end

  defp node_violations({{:., meta, [receiver, function]}, _call_meta, _args}, _path, exceptions)
       when is_atom(function) do
    cond do
      function in [:__schema__, :__struct__] -> [{meta[:line], "inspects a schema with #{function}"}]
      function == :adapter_config -> [{meta[:line], "reads the adapter config"}]
      repo?(receiver) and :repo not in exceptions -> [{meta[:line], "calls a repo"}]
      match?({:__aliases__, _meta, _parts}, receiver) -> module_violations(elem(receiver, 2), meta, exceptions)
      true -> []
    end
  end

  defp node_violations(_node, _path, _exceptions), do: []

  defp module_violations(parts, meta, exceptions) do
    if forbidden_module?(parts, exceptions), do: [{meta[:line], "uses #{Enum.join(parts, ".")}"}], else: []
  end

  defp forbidden_module?([:Ecto, :Changeset | _rest], _exceptions), do: false
  defp forbidden_module?([:Ecto, :Query | _rest], exceptions), do: :query not in exceptions
  defp forbidden_module?([:Ecto | _rest], _exceptions), do: true
  defp forbidden_module?([:Postgrex | _rest], _exceptions), do: true
  defp forbidden_module?([:Backpex, :Adapters | _rest], _exceptions), do: true
  defp forbidden_module?(_parts, _exceptions), do: false

  defp repo?({:repo, _meta, context}) when is_atom(context), do: true
  defp repo?({:__aliases__, _meta, parts}), do: List.last(parts) == :Repo
  defp repo?(_receiver), do: false

  defp template_violations(template, path, line) do
    @template_violation
    |> Regex.scan(template)
    |> Enum.map(fn [match | _groups] ->
      message = "mentions #{String.trim_trailing(match, ".")} in a template"
      if path, do: "#{path}:#{line}: #{message}", else: message
    end)
  end
end
