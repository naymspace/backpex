defmodule Backpex.OptionCoverageTest do
  @moduledoc """
  Line coverage does not show whether every option of Backpex is tested. This test reads the options of the LiveResource,
  the router, the Ecto adapter and every field from their NimbleOptions schemas and fails for each option that no test
  or fixture configures.

  An option counts as configured when its key appears in the matching place of a test or support file:

  - LiveResource options in `use Backpex.LiveResource, ...`,
  - adapter options in its `adapter_config: [...]`,
  - router options in the options of `live_resources/3`,
  - field options in a map or keyword list with `module: <the field module>`.

  Options without a test are listed in `@untested`. Remove an option from that list when you add a test for it, add one
  only with a reason.
  """
  use ExUnit.Case, async: true

  @untested %{
    :field => [:can?, :default, :render_form],
    :live_resource => [:adapter, :layout, :order_nulls, :per_page_default, :per_page_options, :pubsub],
    {:field, Backpex.Fields.BelongsTo} => [:debounce, :display_field_form, :throttle],
    {:field, Backpex.Fields.Boolean} => [:debounce, :throttle],
    {:field, Backpex.Fields.Checkgroup} => [:readonly],
    {:field, Backpex.Fields.Currency} => [
      :debounce,
      :radix,
      :symbol_space,
      :thousands_separator,
      :throttle,
      :unit,
      :unit_position
    ],
    {:field, Backpex.Fields.Date} => [:debounce, :throttle],
    {:field, Backpex.Fields.DateTime} => [:debounce, :throttle],
    {:field, Backpex.Fields.Email} => [:debounce, :placeholder, :throttle],
    {:field, Backpex.Fields.HasMany} => [:display_field_form, :link_assocs, :not_found_text, :prompt],
    {:field, Backpex.Fields.HasManyThrough} => [:sort_by],
    {:field, Backpex.Fields.MultiSelect} => [:not_found_text, :prompt],
    {:field, Backpex.Fields.Number} => [:debounce, :placeholder, :throttle],
    {:field, Backpex.Fields.Select} => [:debounce, :throttle],
    {:field, Backpex.Fields.Text} => [:debounce, :throttle],
    {:field, Backpex.Fields.Textarea} => [:debounce, :placeholder, :throttle],
    {:field, Backpex.Fields.Time} => [:debounce, :throttle],
    {:field, Backpex.Fields.URL} => [:allowed_schemes, :debounce, :throttle],
    {:field, Backpex.Fields.Upload} => [:external, :file_label]
  }

  test "every option is configured by a test or listed as untested" do
    used = used_options()

    for_result =
      for {scope, options} <- schemas(), option <- options, option not in Map.get(used, scope, []), reduce: %{} do
        acc -> Map.update(acc, scope, [option], &[option | &1])
      end

    untested =
      for_result
      |> Map.new(fn {scope, options} -> {scope, Enum.sort(options)} end)

    assert untested == @untested, """
    The options without a test changed.

    Untested now: #{inspect(untested, pretty: true)}

    Add a test for a new option, or remove an option from @untested once a test configures it.
    """
  end

  defp schemas do
    field_modules =
      for module <- backpex_modules(),
          Backpex.Field in (module.__info__(:attributes) |> Keyword.get_values(:behaviour) |> List.flatten()),
          into: %{} do
        {{:field, module}, Keyword.keys(module.config_schema())}
      end

    Map.merge(field_modules, %{
      field: Keyword.keys(Backpex.Field.default_config_schema()),
      live_resource: attribute_keys("lib/backpex/live_resource.ex", :options_schema),
      live_resources: attribute_keys("lib/backpex/router.ex", :live_resources_options),
      adapter_config: attribute_keys("lib/backpex/adapters/ecto.ex", :config_schema)
    })
  end

  defp backpex_modules do
    {:ok, modules} = :application.get_key(:backpex, :modules)
    Enum.each(modules, &Code.ensure_loaded!/1)
    modules
  end

  # The keys of a module attribute that holds a keyword list literal, e.g. `@options_schema [adapter: [...], ...]`.
  defp attribute_keys(path, attribute) do
    {_ast, keys} =
      path
      |> File.read!()
      |> Code.string_to_quoted!()
      |> Macro.prewalk(nil, fn
        {:@, _meta, [{^attribute, _attr_meta, [keyword]}]} = node, nil when is_list(keyword) ->
          {node, Keyword.keys(keyword)}

        node, acc ->
          {node, acc}
      end)

    keys || raise "#{path} has no @#{attribute} keyword list"
  end

  defp used_options do
    "{test,integration_test}/**/*.{ex,exs}"
    |> Path.wildcard()
    |> Enum.reject(&(&1 == Path.relative_to_cwd(__ENV__.file)))
    |> Enum.flat_map(&file_options/1)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {scope, keys} -> {scope, Enum.uniq(keys)} end)
  end

  defp file_options(path) do
    ast = path |> File.read!() |> Code.string_to_quoted!()
    aliases = aliases(ast)

    {_ast, options} =
      Macro.prewalk(ast, [], fn node, acc -> {node, node_options(node, aliases) ++ acc} end)

    options
  end

  defp node_options({:use, _meta, [{:__aliases__, _alias_meta, [:Backpex, :LiveResource]}, opts]}, _aliases)
       when is_list(opts) do
    adapter_config = Keyword.get(opts, :adapter_config, [])
    adapter_keys = if Keyword.keyword?(adapter_config), do: Keyword.keys(adapter_config), else: []

    live_resource_options = opts |> Keyword.keys() |> Enum.map(&{:live_resource, &1})

    live_resource_options ++ Enum.map(adapter_keys, &{:adapter_config, &1})
  end

  defp node_options({:live_resources, _meta, [_path, _live_resource, opts]}, _aliases) when is_list(opts) do
    opts |> Keyword.keys() |> Enum.map(&{:live_resources, &1})
  end

  defp node_options({:%{}, _meta, pairs}, aliases), do: field_options(pairs, aliases)

  defp node_options(list, aliases) when is_list(list) do
    if list != [] and Keyword.keyword?(list), do: field_options(list, aliases), else: []
  end

  defp node_options(_node, _aliases), do: []

  defp field_options(pairs, aliases) do
    with true <- Keyword.keyword?(pairs),
         {:ok, module_ast} <- Keyword.fetch(pairs, :module),
         module when is_atom(module) <- resolve(module_ast, aliases),
         "Elixir.Backpex.Fields." <> _name <- Atom.to_string(module) do
      keys = Keyword.keys(pairs)
      Enum.map(keys, &{{:field, module}, &1}) ++ Enum.map(keys, &{:field, &1})
    else
      _other -> []
    end
  end

  defp resolve({:__aliases__, _meta, [first | rest]}, aliases) do
    case Map.fetch(aliases, first) do
      {:ok, parts} -> safe_concat(parts ++ rest)
      :error -> safe_concat([first | rest])
    end
  end

  defp resolve(_ast, _aliases), do: nil

  # A module that doesn't exist can't be a field module.
  defp safe_concat(parts) do
    Module.safe_concat(parts)
  rescue
    ArgumentError -> nil
  end

  # `alias A.B`, `alias A.B, as: C` and `alias A.{B, C}`, as a map of the short name to the parts of the full name.
  defp aliases(ast) do
    {_ast, aliases} =
      Macro.prewalk(ast, %{}, fn
        {:alias, _meta, [{:__aliases__, _alias_meta, parts}]} = node, acc ->
          {node, Map.put(acc, List.last(parts), parts)}

        {:alias, _meta, [{:__aliases__, _alias_meta, parts}, [as: {:__aliases__, _as_meta, [name]}]]} = node, acc ->
          {node, Map.put(acc, name, parts)}

        {:alias, _meta, [{{:., _dot_meta, [{:__aliases__, _base_meta, base}, :{}]}, _multi_meta, children}]} = node,
        acc ->
          {node,
           Enum.reduce(children, acc, fn {:__aliases__, _child_meta, parts}, acc ->
             Map.put(acc, List.last(parts), base ++ parts)
           end)}

        node, acc ->
          {node, acc}
      end)

    aliases
  end
end
