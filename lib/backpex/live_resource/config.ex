defmodule Backpex.LiveResource.Config do
  @moduledoc false

  # Validates what a LiveResource returns from `filters/1`, `metrics/0`, `item_actions/1`, `resource_actions/0` and
  # `panels/0`, as `Backpex.Field` does for `fields/0`. The schemas live in the modules that document them:
  # `Backpex.Filter`, `Backpex.Metric`, `Backpex.ItemAction` and `Backpex.ResourceAction`.

  @panels_schema [*: [type: :string]]

  @doc """
  Validates a keyword list of configuration maps and returns it unchanged.

  `validate` receives the options of one entry as a keyword list and returns the result of `NimbleOptions.validate/2`.
  `kind` names one entry in the error message (e.g. `"filter"`), `callback` the LiveResource callback the list comes
  from (e.g. `"filters/1"`).
  """
  def validate_each!(configs, kind, callback, live_resource, validate) when is_list(configs) do
    Enum.each(configs, fn
      {key, config} when is_atom(key) and is_map(config) and not is_struct(config) ->
        case validate.(Keyword.new(config)) do
          {:ok, _validated_options} -> :ok
          {:error, error} -> raise ArgumentError, entry_message(kind, key, live_resource, Exception.message(error))
        end

      other ->
        raise ArgumentError, shape_message(callback, live_resource, "a keyword list of maps", other)
    end)

    configs
  end

  def validate_each!(configs, _kind, callback, live_resource, _validate) do
    raise ArgumentError, shape_message(callback, live_resource, "a keyword list of maps", configs)
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
