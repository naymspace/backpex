defmodule Backpex.Adapters.Ecto.Where do
  @moduledoc false
  # Turns a `Backpex.Expr` into a `where` clause of an Ecto query.
  #
  # Fields of the items are fields of the first binding. A path through relationships to one item joins them with left
  # joins, named after the path, so every expression that uses the same path shares the join. `exists` becomes a
  # subquery of the primary keys of the items with a matching related item, so it never duplicates items.

  import Ecto.Query

  alias Backpex.Expr
  alias Backpex.Expr.Call
  alias Backpex.Expr.Exists
  alias Backpex.Expr.Native
  alias Backpex.Expr.Ref

  @comparisons [:==, :!=, :<, :<=, :>, :>=]
  @flipped %{:== => :==, :!= => :!=, :< => :>, :<= => :>=, :> => :<, :>= => :<=}
  @string_functions [:contains, :starts_with, :ends_with]

  @doc """
  Adds the expression to the query as a `where` clause. Keeps the query for a `nil` expression.
  """
  def where_expr(_query, %Ecto.Query.DynamicExpr{} = expression) do
    raise ArgumentError, """
    expected an expression, got an Ecto dynamic expression: #{inspect(expression)}

    Wrap it with Backpex.Expr.native(Backpex.Adapters.Ecto, dynamic(...)), see Backpex.Expr.
    """
  end

  def where_expr(query, expression) do
    case Expr.normalize(expression) do
      nil ->
        query

      expression ->
        query = Ecto.Queryable.to_query(query)
        {query, condition} = to_dynamic(expression, query, {:root, schema(query)})

        where(query, ^condition)
    end
  end

  @doc """
  Returns the query with the joins of the path of the ref and a dynamic expression of its field, e.g. to sort by it.
  """
  def field(query, %Ref{} = ref) do
    query = Ecto.Queryable.to_query(query)

    field(ref, query, {:root, schema(query)})
  end

  @doc """
  Returns the query with the joins the expression needs and a dynamic expression of its value, e.g. of a computed
  value: a field, `concat`, a condition or a native expression.
  """
  def value(query, expression) do
    query = Ecto.Queryable.to_query(query)

    value(expression, query, {:root, schema(query)})
  end

  @doc """
  Returns the query with the left joins of the relationships of `path` and the name of the binding at its end, e.g.
  `:backpex_author` for `[:author]`, or `nil` for an empty path.
  """
  def binding(query, path) do
    query = Ecto.Queryable.to_query(query)

    case join_path(query, path, {:root, schema(query)}, :left) do
      {query, {:root, _schema}} -> {query, nil}
      {query, {name, _schema}} -> {query, name}
    end
  end

  defp value(%Ref{} = ref, query, binding), do: field(ref, query, binding)

  defp value(%Call{name: :concat, args: parts, opts: opts}, query, binding) do
    separator = Keyword.get(opts, :separator, "")

    {texts, query} = Enum.map_reduce(parts, query, &text(&1, &2, binding))

    # `concat_ws` leaves out NULL. Joining the parts one by one, an empty string of the parts before stands for NULL.
    joined =
      Enum.reduce(texts, nil, fn
        text, nil -> text
        text, joined -> dynamic(fragment("concat_ws(?, NULLIF(?, ''), ?)", ^separator, ^joined, ^text))
      end)

    {query, joined || dynamic(fragment("''"))}
  end

  defp value(%struct{} = expression, query, binding) when struct in [Call, Exists, Native],
    do: to_dynamic(expression, query, binding)

  defp value(value, _query, _binding) do
    raise ArgumentError, "expected an expression such as a field or concat(...) as a value, got: #{inspect(value)}"
  end

  # A part of `concat` as text.
  defp text(part, query, _binding) when is_binary(part), do: {dynamic(fragment("CAST(? AS TEXT)", ^part)), query}

  defp text(part, query, binding) do
    {query, value} = value(part, query, binding)

    {dynamic(fragment("CAST(? AS TEXT)", ^value)), query}
  end

  # A binding is `{:root, schema}` for the first binding or `{name, schema}` for a named one. A native expression gets
  # the joins of the paths it uses.
  defp to_dynamic(
         %Native{adapter: Backpex.Adapters.Ecto, expr: %Ecto.Query.DynamicExpr{} = expression, uses: uses},
         query,
         binding
       ) do
    query = Enum.reduce(uses, query, fn path, query -> query |> join_path(path, binding, :left) |> elem(0) end)

    {query, expression}
  end

  defp to_dynamic(%Native{} = expression, _query, _binding) do
    raise ArgumentError,
          "expected a native expression of Backpex.Adapters.Ecto with an Ecto dynamic expression, got: " <>
            inspect(expression)
  end

  defp to_dynamic(%Call{name: :and, args: []}, query, _binding), do: {query, dynamic(true)}
  defp to_dynamic(%Call{name: :or, args: []}, query, _binding), do: {query, dynamic(false)}

  defp to_dynamic(%Call{name: operator, args: [expression | expressions]}, query, binding)
       when operator in [:and, :or] do
    {query, condition} = to_dynamic(expression, query, binding)

    Enum.reduce(expressions, {query, condition}, fn expression, {query, condition} ->
      {query, next} = to_dynamic(expression, query, binding)

      case operator do
        :and -> {query, dynamic(^condition and ^next)}
        :or -> {query, dynamic(^condition or ^next)}
      end
    end)
  end

  defp to_dynamic(%Call{name: :not, args: [expression]}, query, binding) do
    {query, condition} = to_dynamic(expression, query, binding)

    {query, dynamic(not (^condition))}
  end

  defp to_dynamic(%Call{name: :is_nil, args: [%Ref{} = ref]}, query, binding) do
    {query, field} = field(ref, query, binding)

    {query, dynamic(is_nil(^field))}
  end

  defp to_dynamic(%Call{name: operator, args: [%Ref{} = left, %Ref{} = right]}, query, binding)
       when operator in @comparisons do
    {query, left} = field(left, query, binding)
    {query, right} = field(right, query, binding)

    {query, compare_fields(operator, left, right)}
  end

  defp to_dynamic(%Call{name: operator, args: [%Ref{} = ref, value]}, query, binding) when operator in @comparisons do
    {query, {binding, name}} = resolve(ref, query, binding)

    {query, compare(operator, binding, name, value)}
  end

  defp to_dynamic(%Call{name: operator, args: [value, %Ref{} = ref]} = call, query, binding)
       when operator in @comparisons do
    to_dynamic(%{call | name: Map.fetch!(@flipped, operator), args: [ref, value]}, query, binding)
  end

  defp to_dynamic(%Call{name: :in, args: [%Ref{} = ref, values]} = call, query, binding) when is_list(values) do
    # As in SQL, `nil` would never match, and in a negated expression it would keep no items at all.
    if nil in values do
      raise ArgumentError,
            "expected the values of in not to contain nil, got: #{inspect(call)}. " <>
              "Combine the expression with is_nil(#{ref.name}) in an or instead"
    end

    {query, {binding, name}} = resolve(ref, query, binding)

    {query, in_values(binding, name, values)}
  end

  defp to_dynamic(%Call{name: function, args: [%Ref{} = ref, value], opts: opts}, query, binding)
       when function in @string_functions and is_binary(value) do
    {query, field} = field(ref, query, binding)
    pattern = pattern(function, value)

    if Keyword.get(opts, :ignore_case, false) do
      {query, dynamic(ilike(^field, ^pattern))}
    else
      {query, dynamic(like(^field, ^pattern))}
    end
  end

  defp to_dynamic(%Exists{path: [_relationship | _rest] = path, where: expression}, query, {_kind, schema} = binding) do
    primary_key = primary_key!(schema)

    {subquery, target} =
      from(item in schema, select: field(item, ^primary_key))
      |> join_path(path, {:root, schema}, :inner)

    subquery =
      case Expr.normalize(expression) do
        nil -> subquery
        expression -> where_in_binding(subquery, expression, target)
      end

    {query, in_subquery(binding, primary_key, subquery)}
  end

  defp to_dynamic(expression, _query, _binding) do
    raise ArgumentError, "unsupported expression: #{inspect(expression)}, see Backpex.Expr"
  end

  defp where_in_binding(query, expression, binding) do
    {query, condition} = to_dynamic(expression, query, binding)

    where(query, ^condition)
  end

  defp field(ref, query, binding) do
    {query, {binding, name}} = resolve(ref, query, binding)

    {query, field_dynamic(binding, name)}
  end

  # Returns the binding of the field of the ref, after joining the relationships of its path.
  defp resolve(%Ref{path: path, name: name}, query, binding) do
    {query, binding} = join_path(query, path, binding, :left)

    {query, {binding, name}}
  end

  defp join_path(query, path, binding, qualifier) do
    Enum.reduce(path, {query, binding}, fn relationship, {query, {_kind, schema} = binding} ->
      association = association!(schema, relationship)

      if qualifier == :left and association.cardinality != :one do
        raise ArgumentError,
              "expected #{inspect(relationship)} to be a relationship to one item in a path of #{inspect(schema)}, " <>
                "use exists(#{relationship}, ...) for a relationship to many items"
      end

      name = binding_name(binding, relationship)

      query =
        if has_named_binding?(query, name), do: query, else: join_assoc(query, qualifier, binding, relationship, name)

      {query, {name, related!(schema, association)}}
    end)
  end

  # The names come from the relationships of the schemas, so there are only as many as the schemas have.
  # sobelow_skip ["DOS.StringToAtom"]
  defp binding_name({binding, _schema}, relationship) do
    name = if binding == :root, do: "backpex_#{relationship}", else: "#{binding}__#{relationship}"

    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    String.to_atom(name)
  end

  defp join_assoc(query, :left, {:root, _schema}, relationship, name),
    do: join(query, :left, [item], related in assoc(item, ^relationship), as: ^name)

  defp join_assoc(query, :left, {binding, _schema}, relationship, name),
    do: join(query, :left, [{^binding, item}], related in assoc(item, ^relationship), as: ^name)

  defp join_assoc(query, :inner, {:root, _schema}, relationship, name),
    do: join(query, :inner, [item], related in assoc(item, ^relationship), as: ^name)

  defp join_assoc(query, :inner, {binding, _schema}, relationship, name),
    do: join(query, :inner, [{^binding, item}], related in assoc(item, ^relationship), as: ^name)

  defp association!(nil = _schema, relationship) do
    raise ArgumentError, "expected a query of an Ecto schema to join #{inspect(relationship)}"
  end

  defp association!(schema, relationship) do
    schema.__schema__(:association, relationship) ||
      raise ArgumentError, "expected #{inspect(schema)} to have an association #{inspect(relationship)}"
  end

  defp related!(_schema, %{related: related}), do: related

  defp related!(schema, %Ecto.Association.HasThrough{through: through}) do
    Enum.reduce(through, schema, fn relationship, schema -> related!(schema, association!(schema, relationship)) end)
  end

  defp primary_key!(schema) do
    case schema.__schema__(:primary_key) do
      [primary_key] ->
        primary_key

      primary_key ->
        raise ArgumentError, "expected #{inspect(schema)} to have one primary key, got: #{inspect(primary_key)}"
    end
  end

  defp schema(%Ecto.Query{from: %{source: {_source, schema}}}) when is_atom(schema), do: schema
  defp schema(_query), do: nil

  defp field_dynamic({:root, _schema}, name), do: dynamic([item], field(item, ^name))
  defp field_dynamic({binding, _schema}, name), do: dynamic([{^binding, item}], field(item, ^name))

  defp compare_fields(operator, left, right) do
    case operator do
      :== -> dynamic(^left == ^right)
      :!= -> dynamic(^left != ^right)
      :< -> dynamic(^left < ^right)
      :<= -> dynamic(^left <= ^right)
      :> -> dynamic(^left > ^right)
      :>= -> dynamic(^left >= ^right)
    end
  end

  # The value is compared to the field itself, not to a dynamic of it, so Ecto casts the value to the type of the field.
  defp compare(operator, {:root, _schema}, name, value) do
    case operator do
      :== -> dynamic([item], field(item, ^name) == ^value)
      :!= -> dynamic([item], field(item, ^name) != ^value)
      :< -> dynamic([item], field(item, ^name) < ^value)
      :<= -> dynamic([item], field(item, ^name) <= ^value)
      :> -> dynamic([item], field(item, ^name) > ^value)
      :>= -> dynamic([item], field(item, ^name) >= ^value)
    end
  end

  defp compare(operator, {binding, _schema}, name, value) do
    case operator do
      :== -> dynamic([{^binding, item}], field(item, ^name) == ^value)
      :!= -> dynamic([{^binding, item}], field(item, ^name) != ^value)
      :< -> dynamic([{^binding, item}], field(item, ^name) < ^value)
      :<= -> dynamic([{^binding, item}], field(item, ^name) <= ^value)
      :> -> dynamic([{^binding, item}], field(item, ^name) > ^value)
      :>= -> dynamic([{^binding, item}], field(item, ^name) >= ^value)
    end
  end

  defp in_values({:root, _schema}, name, values), do: dynamic([item], field(item, ^name) in ^values)
  defp in_values({binding, _schema}, name, values), do: dynamic([{^binding, item}], field(item, ^name) in ^values)

  defp in_subquery({:root, _schema}, primary_key, subquery),
    do: dynamic([item], field(item, ^primary_key) in subquery(subquery))

  defp in_subquery({binding, _schema}, primary_key, subquery),
    do: dynamic([{^binding, item}], field(item, ^primary_key) in subquery(subquery))

  defp pattern(function, value) do
    escaped = String.replace(value, ["\\", "%", "_"], &("\\" <> &1))

    case function do
      :contains -> "%" <> escaped <> "%"
      :starts_with -> escaped <> "%"
      :ends_with -> "%" <> escaped
    end
  end
end
