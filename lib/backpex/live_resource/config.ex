defmodule Backpex.LiveResource.Config do
  @moduledoc false

  # Validates what a LiveResource returns from `filters/1`, `metrics/0`, `item_actions/1`, `resource_actions/0` and
  # `panels/0`, as `Backpex.Field` does for `fields/0`. The schemas live in the modules that document them:
  # `Backpex.Filter`, `Backpex.Metric`, `Backpex.ItemAction` and `Backpex.ResourceAction`.
  #
  # The module of a filter, metric or action can read its whole map, so the map may hold options of the module's own.
  # A module that implements `config_schema/0` declares them and its map is validated strictly; for any other module
  # only the options of the base schema are validated and other keys are passed on.

  # Compiled once: `NimbleOptions.validate/2` validates a keyword list schema itself on every call.
  @panels_schema NimbleOptions.new!(*: [type: {:or, [:string, nil]}])

  @doc """
  Validates a keyword list of configuration maps and returns it unchanged.

  `validate` receives the options of one entry as a keyword list and returns the result of `NimbleOptions.validate/2`.
  `kind` names one entry in the error message (e.g. `"filter"`), `callback` the LiveResource callback the list comes
  from (e.g. `"filters/1"`).
  """
  def validate_each!(configs, kind, callback, live_resource, validate) when is_list(configs) do
    Enum.each(configs, fn
      {key, config} when is_atom(key) and is_map(config) and not is_struct(config) ->
        validate_entry!(config, kind, key, live_resource, validate)

      other ->
        raise ArgumentError, shape_message(callback, live_resource, "a keyword list of maps", other)
    end)

    configs
  end

  def validate_each!(configs, _kind, callback, live_resource, _validate) do
    raise ArgumentError, shape_message(callback, live_resource, "a keyword list of maps", configs)
  end

  defp validate_entry!(config, kind, key, live_resource, validate) do
    if config |> Map.keys() |> Enum.any?(&(not is_atom(&1))) do
      raise ArgumentError,
            entry_message(kind, key, live_resource, "expected a map with atom keys, got: #{inspect(config)}")
    end

    options = Map.to_list(config)

    case validate.(options) do
      {:ok, _validated_options} -> :ok
      {:error, error} -> raise ArgumentError, entry_message(kind, key, live_resource, Exception.message(error))
    end
  end

  @doc """
  Validates the options of one entry against `base_schema` and, if the module in `:module` implements
  `config_schema/0`, its schema. `compiled_base_schema` is `base_schema` compiled with `NimbleOptions.new!/1`.
  """
  def validate_options(options, base_schema, compiled_base_schema) do
    module = options[:module]

    if is_atom(module) and Code.ensure_loaded?(module) and function_exported?(module, :config_schema, 0) do
      NimbleOptions.validate(options, compiled_module_schema(module, base_schema))
    else
      options
      |> Keyword.take(Keyword.keys(base_schema))
      |> NimbleOptions.validate(compiled_base_schema)
    end
  end

  # The schema of a module is only known at runtime, so the compiled schema is kept in a persistent term. It is
  # compiled again only after the module or the base schema changed: an update of the term triggers a global garbage
  # collection.
  defp compiled_module_schema(module, base_schema) do
    key = {__MODULE__, module}
    version = {module.module_info(:md5), :erlang.phash2(base_schema)}

    case :persistent_term.get(key, nil) do
      {^version, compiled_schema} ->
        compiled_schema

      _other ->
        compiled_schema = base_schema |> merge_schemas(module.config_schema()) |> NimbleOptions.new!()
        :persistent_term.put(key, {version, compiled_schema})
        compiled_schema
    end
  end

  # The module may describe an option of the base schema again, e.g. with its own doc, but cannot make a required one
  # optional.
  defp merge_schemas(base_schema, module_schema) do
    Keyword.merge(base_schema, module_schema, fn _key, base_spec, module_spec ->
      if base_spec[:required], do: Keyword.put(module_spec, :required, true), else: module_spec
    end)
  end

  @doc """
  Validates the keyword list returned by `c:Backpex.LiveResource.panels/0` and returns it unchanged.
  """
  def validate_panels!(panels, live_resource) do
    if Keyword.keyword?(panels) do
      case NimbleOptions.validate(panels, @panels_schema) do
        {:ok, _validated_panels} -> panels
        {:error, error} -> raise ArgumentError, entry_message("panel", error.key, live_resource, error.message)
      end
    else
      raise ArgumentError, shape_message("panels/0", live_resource, "a keyword list of labels", panels)
    end
  end

  defp entry_message(kind, key, live_resource, message) do
    """
    Configuration error for #{kind} "#{key}" in "#{live_resource}".

    #{message}
    """
  end

  defp shape_message(callback, live_resource, expected, got) do
    """
    Configuration error for #{callback} in "#{live_resource}".

    expected #{expected}, got: #{inspect(got)}
    """
  end
end
