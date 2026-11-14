defmodule Backpex.Query.Runtime do
  @moduledoc false
  # Applies the parts of a `Backpex.Query` to items in memory, see `Backpex.Query.apply_to/2`.
  #
  # Expressions follow the three-valued logic of SQL: a comparison with `nil` is unknown (`nil` here), `not` keeps it
  # unknown, and an item is only kept if its expression is `true`. Sorting puts `nil` last when ascending and first when
  # descending, as PostgreSQL does, unless the direction says otherwise.

  alias Backpex.Expr.Call
  alias Backpex.Expr.Exists
  alias Backpex.Expr.Native
  alias Backpex.Expr.Ref

  @comparisons [:==, :!=, :<, :<=, :>, :>=]

  ## Filter and search

  def filter(items, nil), do: items
  def filter(items, expression), do: Enum.filter(items, &(eval(expression, &1) == true))

  def search(items, nil), do: items
  def search(items, %{targets: []}), do: items

  def search(items, %{term: term, targets: targets}) do
    term = String.downcase(term)

    Enum.filter(items, fn item -> Enum.any?(targets, &contains_term?(value(&1, item), term)) end)
  end

  defp contains_term?(nil, _term), do: false
  defp contains_term?(value, term), do: value |> to_text() |> String.downcase() |> String.contains?(term)

  defp to_text(value) when is_binary(value), do: value
  defp to_text(value) when is_atom(value) or is_number(value), do: to_string(value)
  defp to_text(%_struct{} = value), do: if(String.Chars.impl_for(value), do: to_string(value), else: inspect(value))

  # Values without a text form, e.g. lists and maps of embeds, are searched in their inspected form.
  defp to_text(value), do: inspect(value)

  @doc false
  def eval(%Native{} = expression, _item) do
    raise ArgumentError, "can't apply the native expression #{inspect(expression)} to items in memory"
  end

  def eval(%Call{name: :and, args: args}, item) do
    Enum.reduce_while(args, true, fn expression, acc ->
      case eval(expression, item) do
        false -> {:halt, false}
        nil -> {:cont, nil}
        true -> {:cont, acc}
      end
    end)
  end

  def eval(%Call{name: :or, args: args}, item) do
    Enum.reduce_while(args, false, fn expression, acc ->
      case eval(expression, item) do
        true -> {:halt, true}
        nil -> {:cont, nil}
        false -> {:cont, acc}
      end
    end)
  end

  def eval(%Call{name: :not, args: [expression]}, item) do
    case eval(expression, item) do
      nil -> nil
      result -> not result
    end
  end

  def eval(%Call{name: :is_nil, args: [ref]}, item), do: is_nil(operand(ref, item))

  def eval(%Call{name: operator, args: [left, right]}, item) when operator in @comparisons do
    compare(operator, operand(left, item), operand(right, item))
  end

  # As in SQL, a value that is not in the list is unknown if the list contains `nil`.
  def eval(%Call{name: :in, args: [ref, values]}, item) when is_list(values) do
    case operand(ref, item) do
      nil -> nil
      value -> Enum.any?(values, &(compare(:==, value, &1) == true)) or if(nil not in values, do: false)
    end
  end

  def eval(%Call{name: function, args: [ref, part], opts: opts}, item)
      when function in [:contains, :starts_with, :ends_with] do
    case operand(ref, item) do
      nil ->
        nil

      value ->
        {value, part} =
          if Keyword.get(opts, :ignore_case, false),
            do: {String.downcase(value), String.downcase(part)},
            else: {value, part}

        case function do
          :contains -> String.contains?(value, part)
          :starts_with -> String.starts_with?(value, part)
          :ends_with -> String.ends_with?(value, part)
        end
    end
  end

  def eval(%Exists{path: path, where: where}, item) do
    item
    |> related(path)
    |> Enum.any?(fn related -> is_nil(where) or eval(where, related) == true end)
  end

  def eval(expression, _item), do: raise(ArgumentError, "unsupported expression: #{inspect(expression)}")

  defp operand(%Ref{} = ref, item), do: value(ref, item)
  defp operand(value, _item), do: value

  @doc false
  def value(%Ref{path: path, name: name}, item) do
    case related_item(item, path) do
      %{} = related -> fetch_field!(related, name)
      _other -> nil
    end
  end

  # The related item at the end of a path through relationships to one item, or `nil` if there is none.
  defp related_item(item, []), do: item

  defp related_item(item, [name | path]) do
    case fetch_relationship!(item, name) do
      nil ->
        nil

      %{} = related ->
        related_item(related, path)

      other ->
        raise ArgumentError,
              "expected the relationship #{inspect(name)} to be one item or nil, got: #{inspect(other)}. " <>
                "Use exists/2 for a relationship to many items, see Backpex.Expr"
    end
  end

  # The related items of a path through relationships, e.g. the tags of a post. Relationships to one item count as a
  # list of one item.
  defp related(item, []), do: [item]

  defp related(item, [name | path]) do
    item
    |> fetch_relationship!(name)
    |> List.wrap()
    |> Enum.reject(&is_nil/1)
    |> Enum.flat_map(&related(&1, path))
  end

  # A relationship that is not loaded must not count as one without related items, which would keep or drop the wrong
  # items. So an item has to hold every relationship that is read, and a struct every field that is read from it: the
  # placeholder a data source puts into an item for a relationship that is not loaded is a struct without the fields
  # of the related items.
  defp fetch_relationship!(item, name) do
    case item do
      %{^name => related} ->
        related

      _item ->
        raise ArgumentError,
              "can't read the relationship #{inspect(name)} of #{inspect(item)} in memory, as it is not loaded. " <>
                load_hint()
    end
  end

  defp fetch_field!(item, name) do
    case item do
      %{^name => value} ->
        value

      %_struct{} ->
        raise ArgumentError,
              "can't read #{inspect(name)} of #{inspect(item)} in memory, as it has no such field. If it stands for " <>
                "a relationship that is not loaded: " <> load_hint()

      _map ->
        nil
    end
  end

  defp load_hint do
    "An adapter loads the relationships in the :load of a query into the items it returns, see " <>
      "Backpex.Adapter.read/1"
  end

  defp compare(_operator, nil, _right), do: nil
  defp compare(_operator, _left, nil), do: nil

  defp compare(operator, left, right) do
    order = order(left, right)

    case operator do
      :== -> order == :eq
      :!= -> order != :eq
      :< -> order == :lt
      :<= -> order != :gt
      :> -> order == :gt
      :>= -> order != :lt
    end
  end

  # Numbers and decimals compare by their value, other structs such as dates with their module and other values of
  # one type by the term order of Elixir. Values of different types have no order: the term order would give one, e.g.
  # every decimal would be greater than every integer, so these raise.
  defp order(%Decimal{} = left, right) when is_number(right), do: order(left, to_decimal(right))
  defp order(left, %Decimal{} = right) when is_number(left), do: left |> to_decimal() |> order(right)

  defp order(%module{} = left, %module{} = right) do
    # `function_exported?/3` doesn't load the module, and the term order of e.g. dates compares the day first.
    if Code.ensure_loaded?(module) and function_exported?(module, :compare, 2),
      do: module.compare(left, right),
      else: term_order(left, right)
  end

  defp order(left, right) when is_number(left) and is_number(right) do
    cond do
      left == right -> :eq
      left < right -> :lt
      true -> :gt
    end
  end

  defp order(left, right) do
    if type(left) == type(right) do
      term_order(left, right)
    else
      raise ArgumentError,
            "can't compare #{inspect(left)} with #{inspect(right)} in memory, as they are values of different types"
    end
  end

  defp to_decimal(value) when is_integer(value), do: Decimal.new(value)
  defp to_decimal(value) when is_float(value), do: Decimal.from_float(value)

  defp type(%module{}), do: module
  defp type(value) when is_binary(value), do: :binary
  defp type(value) when is_boolean(value), do: :boolean
  defp type(value) when is_atom(value), do: :atom
  defp type(value) when is_number(value), do: :number
  defp type(value) when is_list(value), do: :list
  defp type(value) when is_map(value), do: :map
  defp type(value) when is_tuple(value), do: :tuple
  defp type(_value), do: :other

  defp term_order(left, right) do
    cond do
      left === right -> :eq
      left < right -> :lt
      true -> :gt
    end
  end

  ## Sort

  def sort(items, []), do: items

  def sort(items, sorts) do
    Enum.sort(items, fn left, right -> sorted?(sorts, left, right) end)
  end

  # Whether `left` comes before or with `right`.
  defp sorted?([], _left, _right), do: true

  defp sorted?([{ref, direction} | sorts], left, right) do
    case sort_order(direction, value(ref, left), value(ref, right)) do
      :eq -> sorted?(sorts, left, right)
      :lt -> true
      :gt -> false
    end
  end

  defp sort_order(_direction, nil, nil), do: :eq

  defp sort_order(direction, nil, _right), do: if(nulls_first?(direction), do: :lt, else: :gt)
  defp sort_order(direction, _left, nil), do: if(nulls_first?(direction), do: :gt, else: :lt)

  defp sort_order(direction, left, right) do
    case {descending?(direction), order(left, right)} do
      {_descending, :eq} -> :eq
      {false, order} -> order
      {true, :lt} -> :gt
      {true, :gt} -> :lt
    end
  end

  defp descending?(direction), do: direction in [:desc, :desc_nulls_first, :desc_nulls_last]

  # As in PostgreSQL, `nil` is larger than every value.
  defp nulls_first?(direction), do: direction in [:desc, :asc_nulls_first, :desc_nulls_first]

  ## Pagination

  def paginate(items, offset, limit) do
    items
    |> Enum.drop(offset || 0)
    |> then(&if(limit, do: Enum.take(&1, limit), else: &1))
  end

  ## Aggregates

  def aggregate(items, %{aggregate: aggregate, where: where}) do
    items |> filter(where) |> compute(aggregate)
  end

  defp compute(items, :count), do: length(items)
  defp compute(items, {:count, field}), do: items |> values(field) |> length()
  defp compute(items, {:sum, field}), do: items |> values(field) |> sum()
  defp compute(items, {:avg, field}), do: items |> values(field) |> avg()
  defp compute(items, {:min, field}), do: items |> values(field) |> extreme(:lt)
  defp compute(items, {:max, field}), do: items |> values(field) |> extreme(:gt)

  defp compute(_items, aggregate) do
    raise ArgumentError, "can't compute the aggregate #{inspect(aggregate)} of items in memory"
  end

  defp values(items, field), do: items |> Enum.map(&Map.get(&1, field)) |> Enum.reject(&is_nil/1)

  # As in SQL, the sum, average, minimum and maximum of no values is `nil`.
  defp sum([]), do: nil
  defp sum([%Decimal{} | _rest] = values), do: Enum.reduce(values, &Decimal.add/2)
  defp sum(values), do: Enum.sum(values)

  defp avg([]), do: nil
  defp avg([%Decimal{} | _rest] = values), do: values |> sum() |> Decimal.div(length(values))
  defp avg(values), do: sum(values) / length(values)

  defp extreme([], _order), do: nil

  defp extreme(values, order),
    do: Enum.reduce(values, fn value, acc -> if order(value, acc) == order, do: value, else: acc end)
end
