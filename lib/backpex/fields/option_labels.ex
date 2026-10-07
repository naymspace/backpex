defmodule Backpex.Fields.OptionLabels do
  @moduledoc false

  # Query expressions of fields with options that map the stored values to the labels of their options, so that
  # searching and ordering match what the user sees, e.g. translated labels.

  import Ecto.Query

  @doc """
  Resolves the options of a field. A function receives the assigns with the `:field_options` of the field.
  """
  def options({_name, field_options}, assigns) do
    case Map.get(field_options, :options) do
      options when is_function(options) -> assigns |> Map.put(:field_options, field_options) |> options.()
      options -> options
    end
  end

  @doc """
  Flattens possibly grouped options into a list of `{label, value}` tuples. An option without a label is its own label.
  """
  def flatten(options) do
    options
    |> Enum.map(fn
      {_label, value} = option ->
        case value do
          value when is_list(value) or is_map(value) -> value
          _value -> option
        end

      option ->
        option
    end)
    |> List.flatten()
    |> Enum.map(fn
      {label, value} -> {label, value}
      value -> {value, value}
    end)
  end

  @doc """
  Returns the label of the option of a single stored value. Values without an option fall back to the stored value.
  """
  def label_expression(schema_name, field_name, options) do
    {labels, values} = labels_and_values(options)

    dynamic(
      [{^schema_name, schema_name}],
      fragment(
        "coalesce((?::text[])[array_position(?::text[], ?::text)], ?::text)",
        ^labels,
        ^values,
        schema_name |> field(^field_name),
        schema_name |> field(^field_name)
      )
    )
  end

  @doc """
  Returns the labels of the options of an array of stored values, in the order of the options and joined with `", "`.
  Values without an option are left out. Returns `NULL` if no value has an option, so these rows are ordered like rows
  without a value.
  """
  def labels_expression(schema_name, field_name, options) do
    {labels, values} = labels_and_values(options)

    dynamic(
      [{^schema_name, schema_name}],
      fragment(
        "nullif(array_to_string(array(select (?::text[])[i] from generate_subscripts(?::text[], 1) as i where (?::text[])[i] = any(?::text[]) order by i), ', '), '')",
        ^labels,
        ^labels,
        ^values,
        schema_name |> field(^field_name)
      )
    )
  end

  defp labels_and_values(options) do
    options
    |> flatten()
    |> Enum.map(fn {label, value} -> {to_string(label), to_string(value)} end)
    |> Enum.unzip()
  end
end
