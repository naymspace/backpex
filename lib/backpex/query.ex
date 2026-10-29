defmodule Backpex.Query do
  @moduledoc ~S"""
  A query of the items of a LiveResource, independent of the data source.

  Backpex builds a query for every read: the items of the index view, a single item, the number of items, the data of
  metrics and the options of association fields. The adapter only runs it, with `c:Backpex.Adapter.read/1`,
  `c:Backpex.Adapter.count/1` and `c:Backpex.Adapter.aggregate/1`. The query is public, so you can read the items of the
  index view in your own code, e.g. for an export:

      query =
        assigns
        |> Backpex.LiveResource.index_query()
        |> Backpex.Query.unset([:limit, :offset])

      {:ok, items} = Backpex.Resource.read(query)

  Build a query with the functions of this module, which work like the ones of `Ash.Query`:

      import Backpex.Expr

      MyAppWeb.PostLive
      |> Backpex.Query.new(%{assigns: assigns})
      |> Backpex.Query.filter(expr(published == true))
      |> Backpex.Query.search("elixir", [:title, :body])
      |> Backpex.Query.default_sort(inserted_at: :desc)
      |> Backpex.Query.limit(50)

  ## Fields

    * `:resource` - the LiveResource whose adapter runs the query.
    * `:from` - the path of relationships whose items are read, e.g. `[:author]` for the options of an association
      field. `[]` reads the items of the resource.
    * `:filter` - the expression every item matches, see `Backpex.Expr`. Every call of `filter/2` adds to it with
      `and`. Its fields are fields of the items at the end of `:from`.
    * `:search` - `nil` or a map of the `:term` to search for and the `:targets`, the `Backpex.Expr.Ref`s of the fields
      to search in. An item matches if any target contains the term, ignoring the case. Adapters may search in another
      way, e.g. with full text search.
    * `:sort` and `:default_sort` - lists of a `Backpex.Expr.Ref` and a direction, see `t:direction/0`. The
      `:default_sort` only applies without a `:sort`.
    * `:limit` and `:offset` - limit and skip the items, or `nil`.
    * `:load` - the relationships to load into the items, e.g. for association fields.
    * `:computed` - a map of names to values the adapter computes for every item and puts into it, e.g. an
      `Backpex.Expr.Native` expression.
    * `:aggregates` - the aggregates `c:Backpex.Adapter.aggregate/1` computes, see `aggregate/4`.
    * `:native` - a map of data only the adapter understands, e.g. what `c:Backpex.Adapter.put_field_options/2` takes
      from the options it adds to fields. Backpex doesn't look into it.
    * `:context` - a map of what the query is run for, e.g. `%{assigns: assigns}` with the assigns of the view.
    * `:errors` and `:valid?` - the errors found while building the query, e.g. a primary value that can't be cast. An
      invalid query is not run: `Backpex.Resource.read/1` returns no items for it.
  """

  alias Backpex.Expr
  alias Backpex.Expr.Ref
  alias Backpex.Query.Runtime

  @typedoc """
  The direction of a sort. `:asc` and `:desc` keep the order of `nil` values of the data source.
  """
  @type direction :: :asc | :desc | :asc_nulls_first | :asc_nulls_last | :desc_nulls_first | :desc_nulls_last

  @typedoc """
  An aggregate, see `aggregate/4`.
  """
  @type aggregate :: %{
          name: atom(),
          aggregate: :count | {:count | :sum | :avg | :min | :max, atom() | Expr.t()} | Expr.Native.t(),
          where: Expr.t() | nil
        }

  @type t :: %__MODULE__{
          resource: module(),
          from: [atom()],
          filter: Expr.t() | nil,
          search: %{term: String.t(), targets: [Ref.t()]} | nil,
          sort: [{Ref.t(), direction()}],
          default_sort: [{Ref.t(), direction()}],
          limit: non_neg_integer() | nil,
          offset: non_neg_integer() | nil,
          load: [atom() | {atom(), list() | t()}],
          computed: %{atom() => term()},
          aggregates: [aggregate()],
          native: map(),
          context: map(),
          errors: [term()],
          valid?: boolean()
        }

  defstruct resource: nil,
            from: [],
            filter: nil,
            search: nil,
            sort: [],
            default_sort: [],
            limit: nil,
            offset: nil,
            load: [],
            computed: %{},
            aggregates: [],
            native: %{},
            context: %{},
            errors: [],
            valid?: true

  @directions [:asc, :desc, :asc_nulls_first, :asc_nulls_last, :desc_nulls_first, :desc_nulls_last]
  @aggregate_kinds [:count, :sum, :avg, :min, :max]
  @value_structs [Expr.Ref, Expr.Call, Expr.Aggregate]
  @unset_keys [:filter, :search, :sort, :default_sort, :limit, :offset, :load, :computed, :aggregates]

  @doc """
  Returns a query of the items of the LiveResource. `context` describes what the query is run for, usually
  `%{assigns: assigns}` with the assigns of the view. Adapters read it, e.g. for the `:options_query` of
  `Backpex.Adapters.Ecto`.
  """
  @spec new(module(), map()) :: t()
  def new(live_resource, context \\ %{}) when is_atom(live_resource) and is_map(context) do
    %__MODULE__{resource: live_resource, context: context}
  end

  @doc """
  Reads the items at the end of the path of relationships instead of the items of the resource, e.g. `[:author]` for the
  options of a `Backpex.Fields.BelongsTo` field. Use it before adding filters, as their fields are fields of these
  items.
  """
  @spec from(t(), [atom()]) :: t()
  def from(%__MODULE__{} = query, path) when is_list(path), do: %{query | from: path}

  @doc """
  Adds an expression with `and`, see `Backpex.Expr`. Keeps the query for `nil`.

  The fields of the expression are checked against the description of the items and its values are cast to the types
  of the fields, see `Backpex.Expr.cast/2`. Raises an `ArgumentError` for unknown fields.
  """
  @spec filter(t(), Expr.t() | keyword() | nil) :: t()
  def filter(%__MODULE__{} = query, expression) do
    case Expr.cast(expression, &describe(query, &1)) do
      nil -> query
      expression -> %{query | filter: Expr.all([query.filter, expression])}
    end
  end

  @doc """
  Keeps the item whose primary key is `value`. A value that can't be cast to the type of the primary key makes the
  query invalid, so it reads no items.
  """
  @spec primary(t(), term()) :: t()
  def primary(%__MODULE__{} = query, value) do
    case cast_primary(query, value) do
      {:ok, value} -> filter(query, query |> primary_key() |> Expr.ref() |> equal(value))
      :error -> put_error(query, {:invalid_primary_value, value})
    end
  end

  @doc """
  Keeps the items whose primary key is one of `values`. Values that can't be cast to the type of the primary key are
  ignored.
  """
  @spec primary_in(t(), list()) :: t()
  def primary_in(%__MODULE__{} = query, values) when is_list(values) do
    values =
      Enum.flat_map(values, fn value ->
        case cast_primary(query, value) do
          {:ok, nil} -> []
          {:ok, value} -> [value]
          :error -> []
        end
      end)

    ref = query |> primary_key() |> Expr.ref()

    filter(query, %Expr.Call{name: :in, args: [ref, values]})
  end

  defp equal(ref, value), do: %Expr.Call{name: :==, args: [ref, value]}

  defp primary_key(%__MODULE__{from: [], resource: live_resource}), do: live_resource.config(:primary_key)

  defp primary_key(%__MODULE__{} = query) do
    case describe(query, []) do
      %{primary_key: [primary_key]} -> primary_key
      description -> raise ArgumentError, "expected one primary key in #{inspect(description)}"
    end
  end

  defp cast_primary(query, value) do
    description = describe(query, [])
    type = description && get_in(description.fields, [primary_key(query), :type])

    cond do
      is_nil(value) -> :error
      is_nil(type) -> {:ok, value}
      true -> Expr.cast_value(type, value)
    end
  end

  @doc """
  Searches for `term` in the `targets`. An item matches if any target matches:

    * a field, given as a name, a path such as `"author.name"` or a `Backpex.Expr.Ref`, matches when its value
      contains the term, ignoring the case.
    * any other expression is a condition of its own, e.g. of a field with `c:Backpex.Field.search_condition/3`, and
      matches when it is true. Its fields are checked and its values cast like the ones of `filter/2`.

  Removes the search for a blank term. Without targets, only an adapter with a search of its own, e.g. the full text
  search of `Backpex.Adapters.Ecto`, searches.
  """
  @spec search(t(), String.t() | nil, [atom() | String.t() | Ref.t() | Expr.t()]) :: t()
  def search(%__MODULE__{} = query, term, targets) when is_list(targets) do
    if is_nil(term) or String.trim(term) == "" do
      %{query | search: nil}
    else
      %{query | search: %{term: term, targets: Enum.map(targets, &search_target(query, &1))}}
    end
  end

  defp search_target(%__MODULE__{resource: nil}, %struct{} = condition)
       when struct in [Expr.Call, Expr.Exists, Expr.Native], do: condition

  defp search_target(query, %struct{} = condition) when struct in [Expr.Call, Expr.Exists, Expr.Native],
    do: Expr.cast(condition, &describe(query, &1))

  defp search_target(_query, field), do: to_ref(field)

  @doc """
  Adds sorts, given as a keyword list or a list of tuples of a field and a direction, see `t:direction/0`. A field is a
  name, a path such as `"author.name"` or a `Backpex.Expr.Ref`.
  """
  @spec sort(t(), [{atom() | String.t() | Ref.t(), direction()}]) :: t()
  def sort(%__MODULE__{} = query, sorts) when is_list(sorts), do: %{query | sort: query.sort ++ to_sorts(sorts)}

  @doc """
  Sets the sorts that apply when no other sort is set with `sort/2`, see `sort/2`.
  """
  @spec default_sort(t(), [{atom() | String.t() | Ref.t(), direction()}]) :: t()
  def default_sort(%__MODULE__{} = query, sorts) when is_list(sorts), do: %{query | default_sort: to_sorts(sorts)}

  @doc """
  Returns the sorts the adapter applies: the ones of `sort/2`, or else the ones of `default_sort/2`.
  """
  @spec sorts(t()) :: [{Ref.t(), direction()}]
  def sorts(%__MODULE__{sort: [], default_sort: default_sort}), do: default_sort
  def sorts(%__MODULE__{sort: sort}), do: sort

  @doc """
  Returns the direction of a sort for an ascending or descending `direction` and the `nulls` option of LiveResources and
  fields (`:default`, `:first`, `:last` or `:smallest`).

      iex> Backpex.Query.direction(:asc, :smallest)
      :asc_nulls_first

      iex> Backpex.Query.direction(:desc, :smallest)
      :desc_nulls_last
  """
  @spec direction(:asc | :desc, :default | :first | :last | :smallest) :: direction()
  def direction(direction, :default) when direction in [:asc, :desc], do: direction
  def direction(:asc, :first), do: :asc_nulls_first
  def direction(:asc, :last), do: :asc_nulls_last
  def direction(:desc, :first), do: :desc_nulls_first
  def direction(:desc, :last), do: :desc_nulls_last
  def direction(:asc, :smallest), do: :asc_nulls_first
  def direction(:desc, :smallest), do: :desc_nulls_last

  defp to_sorts(sorts) do
    Enum.map(sorts, fn
      {field, direction} when direction in @directions ->
        {to_ref(field), direction}

      sort ->
        raise ArgumentError, "expected a field and a direction such as {:title, :asc}, got: #{inspect(sort)}"
    end)
  end

  @doc """
  Limits the number of items, or removes the limit with `nil`.
  """
  @spec limit(t(), non_neg_integer() | nil) :: t()
  def limit(%__MODULE__{} = query, limit) when is_nil(limit) or (is_integer(limit) and limit >= 0),
    do: %{query | limit: limit}

  @doc """
  Skips a number of items, or removes the offset with `nil`.
  """
  @spec offset(t(), non_neg_integer() | nil) :: t()
  def offset(%__MODULE__{} = query, offset) when is_nil(offset) or (is_integer(offset) and offset >= 0),
    do: %{query | offset: offset}

  @doc """
  Loads the relationships into the items, given as names or nested like the preloads of Ecto, e.g.
  `[:author, tags: [:category]]`. A relationship can also take a query of `related/1`, which sorts, filters, loads and
  computes values of the related items, e.g. `[comments: Backpex.Query.related(sort: [inserted_at: :desc])]`.
  """
  @spec load(t(), [atom() | {atom(), list() | t()}]) :: t()
  def load(%__MODULE__{} = query, relationships) when is_list(relationships),
    do: %{query | load: Enum.uniq(query.load ++ relationships)}

  @doc """
  Returns a query of related items to load with `load/2`. Takes the options `:filter` (an expression, see
  `Backpex.Expr`), `:sort`, `:load` and `:computed` (a keyword list of names and expressions, see `compute/3`). The
  expressions are not cast, as the query has no resource of its own.

      Backpex.Query.related(
        sort: [year: :asc],
        computed: [full_name: expr(concat([first_name, last_name], " "))]
      )
  """
  @spec related(keyword()) :: t()
  def related(opts \\ []) when is_list(opts) do
    query = %__MODULE__{
      filter: opts |> Keyword.get(:filter) |> Expr.normalize(),
      load: Keyword.get(opts, :load, []),
      computed: opts |> Keyword.get(:computed, []) |> Map.new()
    }

    sort(query, Keyword.get(opts, :sort, []))
  end

  @doc """
  Returns the expression of a computed value the ref names: a value of `:computed` for a ref without a path, or a value
  of the `:computed` of the query of `related/1` the `:load` has for the path, with the path in front of its fields (see
  `Backpex.Expr.prefix/2`). Returns `nil` for a ref of a field.
  """
  @spec computed_expr(t(), Ref.t()) :: Expr.t() | term() | nil
  def computed_expr(%__MODULE__{computed: computed}, %Ref{path: [], name: name}), do: Map.get(computed, name)

  def computed_expr(%__MODULE__{load: load}, %Ref{path: path, name: name}) do
    case related_query(load, path) do
      %__MODULE__{computed: %{^name => expression}} -> Expr.prefix(expression, path)
      _other -> nil
    end
  end

  defp related_query(load, [name]) do
    case List.keyfind(load, name, 0) do
      {^name, %__MODULE__{} = query} -> query
      _other -> nil
    end
  end

  defp related_query(load, [name | path]) do
    case List.keyfind(load, name, 0) do
      {^name, %__MODULE__{load: load}} -> related_query(load, path)
      {^name, load} when is_list(load) -> related_query(load, path)
      _other -> nil
    end
  end

  @doc """
  Lets the adapter compute the value `name` of an expression for every item and put it into the item, e.g.
  `expr(concat([first_name, last_name], " "))`, see the [Values](`m:Backpex.Expr#module-values`) of `Backpex.Expr`.
  Sorts, searches and refs of `computed_expr/2` refer to it by its name.

  The fields of the expression are checked and its values cast like the ones of `filter/2`.
  """
  @spec compute(t(), atom(), Expr.t()) :: t()
  def compute(%__MODULE__{resource: nil} = query, name, expression) when is_atom(name),
    do: %{query | computed: Map.put(query.computed, name, Expr.normalize(expression))}

  def compute(%__MODULE__{} = query, name, expression) when is_atom(name),
    do: %{query | computed: Map.put(query.computed, name, Expr.cast(expression, &describe(query, &1)))}

  @doc """
  Adds an aggregate that `c:Backpex.Adapter.aggregate/1` computes under `name` over the items of the query, e.g. the
  data of a metric. `aggregate` is `:count`, a tuple of `:count`, `:sum`, `:avg`, `:min` or `:max` and the name of a
  field or an expression (e.g. `{:sum, expr(price * quantity)}`, see `Backpex.Expr`), or a `Backpex.Expr.Native`
  expression of the adapter.

  ## Options

    * `:where` - an expression that limits the items of this aggregate, see `Backpex.Expr`.
  """
  @spec aggregate(t(), atom(), aggregate()[:aggregate], keyword()) :: t()
  def aggregate(%__MODULE__{} = query, name, aggregate, opts \\ []) when is_atom(name) do
    aggregate = cast_aggregate!(query, aggregate)
    where = Expr.cast(opts[:where], &describe(query, &1))

    %{query | aggregates: Enum.concat(query.aggregates, [%{name: name, aggregate: aggregate, where: where}])}
  end

  defp cast_aggregate!(_query, :count), do: :count

  defp cast_aggregate!(_query, {kind, field} = aggregate) when kind in @aggregate_kinds and is_atom(field),
    do: aggregate

  defp cast_aggregate!(query, {kind, %struct{} = expression})
       when kind in @aggregate_kinds and struct in @value_structs,
       do: {kind, Expr.cast(expression, &describe(query, &1))}

  defp cast_aggregate!(_query, %Expr.Native{} = aggregate), do: aggregate

  defp cast_aggregate!(_query, aggregate) do
    raise ArgumentError, "expected an aggregate such as :count or {:sum, :field}, got: #{inspect(aggregate)}"
  end

  @doc """
  Removes the given parts of the query, e.g. `unset(query, [:sort, :limit, :offset])` to count all matching items.
  Takes `:filter`, `:search`, `:sort`, `:default_sort`, `:limit`, `:offset`, `:load`, `:computed` and `:aggregates`.
  """
  @spec unset(t(), [atom()]) :: t()
  def unset(%__MODULE__{} = query, keys) when is_list(keys) do
    Enum.reduce(keys, query, fn
      key, query when key in @unset_keys -> Map.put(query, key, Map.fetch!(%__MODULE__{}, key))
      key, _query -> raise ArgumentError, "can't unset #{inspect(key)}, expected one of #{inspect(@unset_keys)}"
    end)
  end

  @doc """
  Applies the filter, the search, the sorts, the offset and the limit of the query to items in memory, e.g. to the items
  of an adapter that doesn't run these parts itself (see `c:Backpex.Adapter.supports?/2`).

  Expressions follow the rules of SQL: a comparison with `nil` keeps no item, not even negated, see `Backpex.Expr`.
  Paths such as `author.name` and `exists/2` read the relationships in the items, so they have to be loaded. The search
  keeps the items that contain the term in any target, ignoring the case. Sorts put `nil` last when ascending and first
  when descending, unless their direction says otherwise. Strings sort by their code points, so `"B"` comes before
  `"a"`. Raises for `Backpex.Expr.Native` expressions.

      iex> items = [%{title: "Elixir", likes: 3}, %{title: "Erlang", likes: nil}, %{title: "Gleam", likes: 5}]
      iex> Backpex.Query.new(MyApp.PostLive)
      ...> |> Map.put(:filter, Backpex.Expr.expr(not starts_with(title, "G")))
      ...> |> Map.put(:sort, [{Backpex.Expr.ref(:likes), :desc}])
      ...> |> Backpex.Query.apply_to(items)
      [%{title: "Erlang", likes: nil}, %{title: "Elixir", likes: 3}]
  """
  @spec apply_to(t(), list()) :: list()
  def apply_to(%__MODULE__{} = query, items) when is_list(items) do
    items
    |> Runtime.compute(query.computed)
    |> Runtime.filter(query.filter)
    |> Runtime.search(query.search)
    |> Runtime.sort(sorts(query))
    |> Runtime.paginate(query.offset, query.limit)
  end

  @doc """
  Computes the `:aggregates` of the query over items in memory, which already match the query, e.g. the items of
  `apply_to/2`. Returns a map of the names of the aggregates to their values, like `c:Backpex.Adapter.aggregate/1`.
  """
  @spec aggregate_items(t(), list()) :: %{atom() => term()}
  def aggregate_items(%__MODULE__{aggregates: aggregates}, items) when is_list(items),
    do: Map.new(aggregates, &{&1.name, Runtime.aggregate(items, &1)})

  @doc """
  Puts data only the adapter understands under `key`, see the `:native` field.
  """
  @spec put_native(t(), term(), term()) :: t()
  def put_native(%__MODULE__{} = query, key, value), do: %{query | native: Map.put(query.native, key, value)}

  @doc """
  Adds an error and makes the query invalid.
  """
  @spec put_error(t(), term()) :: t()
  def put_error(%__MODULE__{} = query, error), do: %{query | errors: Enum.concat(query.errors, [error]), valid?: false}

  @doc """
  Returns a term that is equal for queries that read the same items, e.g. to read the options of association fields
  only once for equal queries. It is the query without its `:context`.

  So an adapter whose items depend on the context, e.g. on the current user in the assigns, puts what they depend on
  into the `:native` field when the query is built, see `c:Backpex.Adapter.put_field_options/2`. The Ecto adapter puts
  the result of the `:options_query` of a field there.
  """
  @spec key(t()) :: map()
  def key(%__MODULE__{} = query), do: query |> Map.from_struct() |> Map.delete(:context)

  @doc """
  Returns the `Backpex.Expr.Ref` of a name, a path such as `"author.name"` or `:"author.name"`, or a ref.

      iex> Backpex.Query.to_ref("author.name")
      %Backpex.Expr.Ref{path: [:author], name: :name}
  """
  @spec to_ref(atom() | String.t() | Ref.t()) :: Ref.t()
  def to_ref(%Ref{} = ref), do: ref
  def to_ref(name) when is_atom(name), do: name |> Atom.to_string() |> to_ref()

  def to_ref(path) when is_binary(path) do
    # Fields and relationships are atoms of the data source, so an unknown name raises instead of creating an atom.
    {path, [name]} = path |> String.split(".") |> Enum.map(&String.to_existing_atom/1) |> Enum.split(-1)

    Expr.ref(path, name)
  end

  defp describe(%__MODULE__{resource: live_resource, from: from}, path),
    do: Backpex.Resource.describe(from ++ path, live_resource)
end
