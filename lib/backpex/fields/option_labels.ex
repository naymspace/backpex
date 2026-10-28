defmodule Backpex.Fields.OptionLabels do
  @moduledoc false

  # Helpers for the `c:Backpex.Field.option_labels/2` callback of fields with options.

  @doc """
  Resolves the options of a field and flattens them into `{label, value}` tuples. A function receives the assigns with
  the `:field_options` of the field.
  """
  def option_labels({_name, field_options}, assigns) do
    options =
      case Map.get(field_options, :options) do
        options when is_function(options) -> assigns |> Map.put(:field_options, field_options) |> options.()
        options -> options
      end

    flatten(options)
  end

  @doc """
  Normalizes all option shapes supported by `Phoenix.HTML.Form.options_for_select/2` into a flat list of
  `{label, value}` tuples. An option without a label is its own label.
  """
  def flatten(options) do
    Enum.flat_map(options, fn
      {:hr, nil} -> []
      {_group_label, group} when is_list(group) or (is_map(group) and not is_struct(group)) -> flatten(group)
      {label, value} -> [{label, value}]
      option when is_list(option) -> [{Keyword.fetch!(option, :key), Keyword.fetch!(option, :value)}]
      :hr -> []
      option -> [{option, option}]
    end)
  end
end
