defmodule Backpex.Resource do
  @moduledoc """
  Generic context module for Backpex resources.

  > ### Work in progress {: .warning}
  >
  > This module is still under heavy development and will change as we progress with the `Backpex.Adapter`
  > implementation in the coming releases. Keep this in mind when using this module directly.

  ## Authorization

  All mutations in this module are authorized through `Backpex.Authorization` before anything else
  happens — before the changeset is built and before `c:Backpex.Field.before_changeset/5` runs. An
  unauthorized call raises `Backpex.ForbiddenError` and never reaches the adapter.

  Each mutation has a default authorization action:

  | function | action | item passed to `c:Backpex.LiveResource.can?/3` |
  | --- | --- | --- |
  | `insert/6` | `:new` | `nil` |
  | `update/6` | `:edit` | the item |
  | `update_all/5` | `:edit` | each item |
  | `delete_all/4` | `:delete` | each item |

  Two options control this on every mutation:

  * `:authorization_action` (atom) — authorize against this action instead of the default. It must
    be a non-nil atom; anything else raises `ArgumentError` rather than being handed to a
    permissive catch-all `can?/3` clause.
  * `:authorize?` (boolean, default `true`) — set to `false` to skip the check entirely. This is the
    escape hatch for system or cascade writes that are not a user-initiated action on that resource,
    for example nullifying foreign keys on another resource.

  Both options are consumed here and never reach `change/6`.

  Before the authorization, every mutation checks that the adapter supports the write (`:insert`, `:update` or
  `:delete`, see `c:Backpex.Adapter.supports?/2`) and raises an `ArgumentError` otherwise, also with another
  `:authorization_action` or `authorize?: false`.

  For lists (`update_all/5`, `delete_all/4`) the check is strict: a single unauthorized item makes
  the whole call raise. A `nil` entry (a stale or forged item id) raises `Backpex.NoResultsError`.
  An empty list passes without calling the adapter's authorization.

  Reads (`read/1`, `get/4`, `get!/4`, `count/1`) are **not** authorized here. `:index` and `:show`
  remain enforced in the view layer — filtering rows after pagination would corrupt counts and
  select-all.
  """

  alias Backpex.Authorization
  alias Backpex.Expr.Call
  alias Backpex.Expr.Exists
  alias Backpex.Expr.Ref
  alias Backpex.Query

  # Counts and aggregates cover all matching items, so these parts of a query don't apply.
  @not_aggregated [:sort, :default_sort, :limit, :offset, :load, :computed]

  @doc """
  Returns the query of the items of the resource that Backpex reads with the given fields: the items of the
  `c:Backpex.LiveResource.scope/1` of the LiveResource, with the relationships of the association fields and the options
  the adapter adds to the fields (see `c:Backpex.Adapter.put_field_options/2`). The `assigns` become the context of the
  query, see `Backpex.Query`.
  """
  @spec items_query(list(), map(), module()) :: Query.t()
  def items_query(fields, assigns, live_resource) do
    live_resource
    |> Query.new(%{assigns: assigns})
    |> Query.filter(scope(live_resource, assigns))
    |> put_fields(fields)
  end

  defp scope(live_resource, assigns) do
    if function_exported?(live_resource, :scope, 1), do: live_resource.scope(assigns)
  end

  defp put_fields(query, fields) do
    Enum.reduce(fields, query, fn {name, field_options} = field, query ->
      query = if association?(field_options.module, field), do: Query.load(query, [name]), else: query

      put_field_options(query, field)
    end)
  end

  defp association?(module, field) do
    Code.ensure_loaded?(module) and function_exported?(module, :association?, 1) and module.association?(field)
  end

  defp put_field_options(%Query{resource: live_resource} = query, field) do
    adapter = live_resource.config(:adapter)

    if Code.ensure_loaded?(adapter) and function_exported?(adapter, :put_field_options, 2),
      do: adapter.put_field_options(query, field),
      else: query
  end

  @doc """
  Returns the items of the query, see `c:Backpex.Adapter.read/1`. An invalid query returns no items.

  The adapter runs the parts of the query it supports (see `c:Backpex.Adapter.supports?/2`), and Backpex applies the
  others to its items with `Backpex.Query.apply_to/2`.
  """
  @spec read(Query.t()) :: {:ok, list()} | {:error, term()}
  def read(%Query{valid?: false}), do: {:ok, []}

  def read(%Query{resource: live_resource} = query) do
    adapter = live_resource.config(:adapter)
    {adapter_query, memory_query} = split(query, adapter)

    case adapter.read(adapter_query) do
      {:ok, items} when memory_query == :none -> {:ok, items}
      {:ok, items} -> {:ok, Query.apply_to(memory_query, items)}
      error -> error
    end
  end

  # The parts of a query, in the order in which they depend on each other, and their keys.
  @stages [filter: [:filter], search: [:search], sort: [:sort, :default_sort], offset: [:offset], limit: [:limit]]

  # Splits the query into the query the adapter runs and the parts Backpex applies in memory (`:none` if the adapter
  # runs all): the first part the adapter doesn't support and every part after it.
  defp split(%Query{resource: live_resource} = query, adapter) do
    {adapter_stages, memory_stages} =
      Enum.split_while(@stages, fn {stage, _keys} -> stage_supported?(query, stage, adapter, live_resource) end)

    memory_keys = Enum.flat_map(memory_stages, fn {_stage, keys} -> keys end)
    adapter_keys = Enum.flat_map(adapter_stages, fn {_stage, keys} -> keys end)

    adapter_query =
      query
      |> Query.unset(memory_keys)
      |> Query.load(memory_relationships(query, Keyword.keys(memory_stages)))

    memory_query =
      if memory_stages == [], do: :none, else: Query.unset(query, [:load, :computed, :aggregates | adapter_keys])

    {adapter_query, memory_query}
  end

  defp stage_supported?(%Query{filter: nil}, :filter, _adapter, _live_resource), do: true

  defp stage_supported?(%Query{filter: filter}, :filter, adapter, live_resource),
    do: filter_supported?(filter, adapter, live_resource)

  defp stage_supported?(%Query{search: nil}, :search, _adapter, _live_resource), do: true

  defp stage_supported?(query, :sort, adapter, live_resource),
    do: Query.sorts(query) == [] or supports?(adapter, live_resource, :sort)

  defp stage_supported?(query, stage, adapter, live_resource),
    do: is_nil(Map.fetch!(query, stage)) or supports?(adapter, live_resource, stage)

  defp filter_supported?(nil = _expression, _adapter, _live_resource), do: true

  defp filter_supported?(expression, adapter, live_resource) do
    supports?(adapter, live_resource, :filter) and
      expression |> operators() |> Enum.all?(&supports?(adapter, live_resource, {:filter, &1}))
  end

  defp supports?(adapter, live_resource, feature) do
    if Code.ensure_loaded?(adapter) and function_exported?(adapter, :supports?, 2),
      do: adapter.supports?(live_resource, feature),
      else: true
  end

  # The operators of an expression, e.g. `:==` or `:exists`. `and`, `or`, `not` and native expressions belong to every
  # filter.
  defp operators(%Call{name: name, args: args}) do
    operators = Enum.flat_map(args, &operators/1)

    if name in [:and, :or, :not], do: operators, else: [name | operators]
  end

  defp operators(%Exists{where: where}), do: [:exists | operators(where)]
  defp operators(_expression), do: []

  # The relationships the parts in memory read, which the adapter has to load into the items.
  defp memory_relationships(query, memory_stages) do
    memory_stages
    |> Enum.flat_map(fn
      :filter -> paths(query.filter)
      :search -> if query.search, do: Enum.map(query.search.targets, & &1.path), else: []
      :sort -> query |> Query.sorts() |> Enum.map(fn {ref, _direction} -> ref.path end)
      _stage -> []
    end)
    |> to_load()
  end

  # The paths of the relationships an expression reads, including the related items of `exists/2`.
  defp paths(%Ref{path: path}), do: [path]
  defp paths(%Call{args: args}), do: Enum.flat_map(args, &paths/1)
  defp paths(%Exists{path: path, where: where}), do: [path | where |> paths() |> Enum.map(&(path ++ &1))]
  defp paths(_expression), do: []

  # The relationships to load for paths, nested like the preloads of Ecto, e.g. `[:author, tags: [:category]]`.
  defp to_load(paths) do
    paths
    |> Enum.reject(&(&1 == []))
    |> Enum.group_by(&hd/1, &tl/1)
    |> Enum.map(fn {name, paths} ->
      case to_load(paths) do
        [] -> name
        nested -> {name, nested}
      end
    end)
  end

  @doc """
  Returns the items of many queries at once, e.g. the options of an association field for every row of the index view.
  Takes a map of keys to queries and returns a map of the same keys to the items. Equal queries are read only once, see
  `Backpex.Query.key/1`.
  """
  @spec read_by_key(%{term() => Query.t()}) :: {:ok, %{term() => list()}}
  def read_by_key(queries_by_key) when is_map(queries_by_key) do
    items_by_query =
      queries_by_key
      |> Map.values()
      |> Enum.uniq_by(&Query.key/1)
      |> Map.new(fn query ->
        {:ok, items} = read(query)
        {Query.key(query), items}
      end)

    {:ok, Map.new(queries_by_key, fn {key, query} -> {key, Map.fetch!(items_by_query, Query.key(query))} end)}
  end

  @doc """
  Returns the number of items the query matches, see `c:Backpex.Adapter.count/1`. Ignores the sorts, the limit, the
  offset and the relationships to load. An invalid query matches no items.
  """
  @spec count(Query.t()) :: {:ok, non_neg_integer()} | {:error, term()}
  def count(%Query{valid?: false}), do: {:ok, 0}

  def count(%Query{resource: live_resource} = query) do
    adapter = live_resource.config(:adapter)
    query = Query.unset(query, @not_aggregated)

    if runs_all?(query, adapter, :count) do
      adapter.count(query)
    else
      with {:ok, items} <- read(query), do: {:ok, length(items)}
    end
  end

  @doc """
  Returns the values of the aggregates of the query, see `c:Backpex.Adapter.aggregate/1`. Ignores the sorts, the limit,
  the offset and the relationships to load. Backpex computes them from the items of `read/1` if the adapter doesn't
  support `:aggregate` or the filter or search of the query.
  """
  @spec aggregate(Query.t()) :: {:ok, %{atom() => term()}} | {:error, term()}
  def aggregate(%Query{aggregates: []}), do: {:ok, %{}}
  def aggregate(%Query{valid?: false, aggregates: aggregates}), do: {:ok, Map.new(aggregates, &{&1.name, nil})}

  def aggregate(%Query{resource: live_resource} = query) do
    adapter = live_resource.config(:adapter)
    query = Query.unset(query, @not_aggregated)

    if runs_all?(query, adapter, :aggregate) do
      adapter.aggregate(query)
    else
      relationships = query.aggregates |> Enum.flat_map(&paths(&1.where)) |> to_load()

      with {:ok, items} <- query |> Query.unset([:aggregates]) |> Query.load(relationships) |> read() do
        {:ok, Query.aggregate_items(query, items)}
      end
    end
  end

  # Whether the adapter runs the callback for the whole query, which counts and aggregates only filter and search.
  defp runs_all?(%Query{resource: live_resource} = query, adapter, callback) do
    Code.ensure_loaded?(adapter) and function_exported?(adapter, callback, 1) and
      supports?(adapter, live_resource, callback) and
      stage_supported?(query, :filter, adapter, live_resource) and
      stage_supported?(query, :search, adapter, live_resource) and
      Enum.all?(query.aggregates, &filter_supported?(&1.where, adapter, live_resource))
  end

  @doc """
  Returns a map of the keys of the metrics to their data for the items of the query, e.g. the query of the index view.

  Calls `c:Backpex.Metric.data/3` with the query if the module of a metric implements it. The aggregates of the other
  metrics are computed by the adapter in one call of `c:Backpex.Adapter.aggregate/1`.
  """
  @spec metrics(keyword(), Query.t(), map()) :: %{atom() => term()}
  def metrics(metrics, %Query{resource: live_resource} = query, assigns) do
    query = Query.unset(query, [:aggregates | @not_aggregated])
    {own, aggregated} = Enum.split_with(metrics, fn {_key, %{module: module}} -> own_data?(module) end)

    {:ok, data} =
      aggregated
      |> Enum.reduce(query, fn {key, metric}, query ->
        Query.aggregate(query, key, metric_aggregate(metric, live_resource), where: Map.get(metric, :where))
      end)
      |> aggregate()

    Enum.reduce(own, data, fn {key, metric}, data -> Map.put(data, key, metric.module.data(metric, query, assigns)) end)
  end

  defp own_data?(module) do
    Code.ensure_loaded(module)

    cond do
      function_exported?(module, :data, 3) ->
        true

      # Backpex no longer calls `query/3`, so the adapter would compute other data than the metric did. `use BackpexWeb,
      # :metric` refuses this at compile time, this covers modules that only declare `@behaviour Backpex.Metric`.
      function_exported?(module, :query, 3) ->
        raise ArgumentError, """
        #{inspect(module)} implements query/3, but metrics no longer query their data. Implement \
        Backpex.Metric.data/3 instead, see the guide on upgrading to v0.24.
        """

      # Backpex no longer calls `data/2` either, `data/3` also receives the query.
      function_exported?(module, :data, 2) ->
        raise ArgumentError, """
        #{inspect(module)} implements data/2, but Backpex calls Backpex.Metric.data/3 with the query of the index \
        view. Implement data/3 instead, see the guide on upgrading to v0.24.
        """

      true ->
        false
    end
  end

  # `Backpex.Adapters.Ecto` takes a `:select` expression instead of an aggregate, see `Backpex.Metric`.
  defp metric_aggregate(%{aggregate: aggregate}, _live_resource), do: aggregate

  defp metric_aggregate(%{select: select}, live_resource),
    do: live_resource.config(:adapter) |> Backpex.Expr.native(select)

  defp metric_aggregate(metric, _live_resource) do
    raise ArgumentError, "expected the metric to have an :aggregate option, got: #{inspect(metric)}"
  end

  @doc """
  Returns a new item that has not been saved yet.
  """
  def new_item(assigns, live_resource) do
    adapter = live_resource.config(:adapter)

    adapter.new_item(assigns, live_resource)
  end

  @doc """
  Returns the description of the items of the resource, or of the related items at the end of the relationships in
  `path`, or `nil` if there is no such path. See `c:Backpex.Adapter.describe/2` and `Backpex.Adapter.Description`.
  """
  @spec describe([atom()], module()) :: Backpex.Adapter.Description.t() | nil
  def describe(path \\ [], live_resource) do
    adapter = live_resource.config(:adapter)

    adapter.describe(path, live_resource)
  end

  @doc """
  Returns the relationship `name` of the resource from its description, or `nil` if there is no such relationship. See
  `Backpex.Adapter.Description` for its keys.
  """
  def association(name, live_resource) do
    Map.get(describe([], live_resource).relationships, name)
  end

  @doc """
  Checks the fields of the expression against the description of the resource and casts the values to the types of the
  fields, see `Backpex.Expr.cast/2`.
  """
  @spec cast_expr(Backpex.Expr.t() | keyword() | nil, module()) :: Backpex.Expr.t() | nil
  def cast_expr(expression, live_resource) do
    Backpex.Expr.cast(expression, &describe(&1, live_resource))
  end

  @doc """
  Returns the query of the items that can be selected as the value of the association field `field`, e.g. the options
  of the select of a `Backpex.Fields.BelongsTo` field: the related items (`:from` is the name of the field) that match
  the `:options_filter` of the field, sorted by its `:options_sort`, with the options the adapter adds to the field
  (e.g. the `:options_query` of `Backpex.Adapters.Ecto`).

  Limit the options further with `Backpex.Query`, e.g. with `Backpex.Query.primary_in/2` or `Backpex.Query.search/3`,
  and read them with `read/1`.
  """
  @spec options_query({atom(), map()}, map(), module()) :: Query.t()
  def options_query({name, field_options} = field, assigns, live_resource) do
    live_resource
    |> Query.new(%{assigns: assigns})
    |> Query.from([name])
    |> Query.filter(options_filter(field_options, assigns))
    |> Query.sort(options_sort(field_options, assigns))
    |> put_field_options(field)
  end

  defp options_filter(%{options_filter: options_filter}, assigns) when is_function(options_filter, 1),
    do: options_filter.(assigns)

  defp options_filter(field_options, _assigns), do: Map.get(field_options, :options_filter)

  defp options_sort(%{options_sort: options_sort}, assigns) when is_function(options_sort, 1),
    do: options_sort.(assigns) || []

  defp options_sort(field_options, _assigns), do: Map.get(field_options, :options_sort, [])

  @doc """
  Returns the items of `options_query/3`, limited by these criteria:

    * `:ids` - only the items with these primary values. Values that are no valid primary value are ignored.
    * `:search` - only the items whose display field contains this string, ignoring the case. Ignored if it is `nil`.
    * `:offset` and `:limit` - skip and limit the items.
  """
  @spec list_options({atom(), map()}, keyword(), map(), module()) :: {:ok, list()} | {:error, term()}
  def list_options(field, criteria, assigns, live_resource) do
    field
    |> options_query(assigns, live_resource)
    |> options_criteria(field, criteria)
    |> read()
  end

  @doc """
  Same as `list_options/4` for many assigns at once, e.g. for the index form of a `Backpex.Fields.BelongsTo` field in
  every row of the index view. Takes a map of keys to assigns and returns a map of the same keys to the items. Equal
  queries are read only once, see `read_by_key/1`.
  """
  @spec list_options_by_key({atom(), map()}, keyword(), map(), module()) :: {:ok, map()}
  def list_options_by_key(field, criteria, assigns_by_key, live_resource) do
    assigns_by_key
    |> Map.new(fn {key, assigns} ->
      {key, field |> options_query(assigns, live_resource) |> options_criteria(field, criteria)}
    end)
    |> read_by_key()
  end

  @doc """
  Returns the number of items `list_options/4` returns for the criteria, ignoring `:offset` and `:limit`.
  """
  @spec count_options({atom(), map()}, keyword(), map(), module()) :: {:ok, non_neg_integer()} | {:error, term()}
  def count_options(field, criteria, assigns, live_resource) do
    field
    |> options_query(assigns, live_resource)
    |> options_criteria(field, Keyword.drop(criteria, [:offset, :limit]))
    |> count()
  end

  defp options_criteria(query, {_name, field_options}, criteria) do
    Enum.reduce(criteria, query, fn
      {:ids, ids}, query -> Query.primary_in(query, ids)
      {:search, search}, query -> Query.search(query, search, List.wrap(field_options[:display_field]))
      {:offset, offset}, query -> Query.offset(query, offset)
      {:limit, limit}, query -> Query.limit(query, limit)
    end)
  end

  @doc """
  Returns a term that changes whenever the options of the association field may change, e.g. when its
  `:options_filter` depends on a value of the form. It is the key of its `options_query/3`, see `Backpex.Query.key/1`.
  """
  @spec options_key({atom(), map()}, map(), module()) :: map()
  def options_key(field, assigns, live_resource), do: field |> options_query(assigns, live_resource) |> Query.key()

  @doc """
  Returns the primitive type of the field `name` of the items from the description of the resource, e.g. `:integer` or
  `:string`, or `nil` if there is no such field.
  """
  def field_type(name, live_resource) do
    case describe([], live_resource).fields do
      %{^name => %{primitive: primitive}} -> primitive
      _fields -> nil
    end
  end

  @doc """
  Gets a database record with the given `fields` by the given  `primary_value`.

  Returns `{:ok, nil}` if no result was found.

  ## Parameters

  * `primary_value`: The identifier for the specific item to be fetched.
  * `assigns` (map): The current assigns of the socket.
  * `live_resource` (module): The `Backpex.LiveResource` module.
  """
  def get(primary_value, fields, assigns, live_resource) do
    query =
      fields
      |> items_query(assigns, live_resource)
      |> Query.primary(primary_value)
      |> Query.limit(1)

    case read(query) do
      {:ok, [item | _rest]} -> {:ok, item}
      {:ok, []} -> {:ok, nil}
      error -> error
    end
  end

  @doc """
  Same as `get/4` but returns the result or raises an error.
  """
  def get!(primary_value, fields, assigns, live_resource) do
    case get(primary_value, fields, assigns, live_resource) do
      {:ok, nil} -> raise Backpex.NoResultsError
      {:ok, result} -> result
      {:error, _error} -> raise Backpex.NoResultsError
    end
  end

  @doc """
  Re-reads a list of items from the data layer, keeping the order of the given list.

  Each item is fetched by its primary value through `get/4`, so the LiveResource's
  [`item_query/3`](item-query.html) applies. An item that no longer exists — or that has left the
  query's scope — comes back as `nil` instead of being dropped, which keeps the result positionally
  aligned with the input and lets `Backpex.Authorization.authorize_all!/4` turn it into a
  `Backpex.NoResultsError`. A `nil` in the input stays `nil`.

  This is what makes the item action execution gates authorize the *current* record rather than the
  snapshot that was cached when the row was selected. See `Backpex.ItemAction.authorize_fresh!/3`.

  Like every other read in this module, this is **not** authorized.

  ## Parameters

  * `items` (list): The items to re-read.
  * `fields` (list): The **resource** fields — they decide which associations are preloaded. Do not
    pass an item action's form fields here.
  * `assigns` (map): The current assigns of the socket.
  * `live_resource` (module): The `Backpex.LiveResource` module.
  """
  def reload(items, fields, assigns, live_resource) when is_list(items) do
    Enum.map(items, fn
      nil ->
        nil

      item ->
        primary_value = Backpex.LiveResource.primary_value(item, live_resource)

        case get(primary_value, fields, assigns, live_resource) do
          {:ok, reloaded_item} -> reloaded_item
          {:error, _error} -> nil
        end
    end)
  end

  @doc """
  Deletes multiple items.
  Additionally broadcasts the corresponding event for each deleted item.

  Returns `{:error, :foreign_key_violation}` if an item can't be deleted because other data still references it.

  Authorizes `:delete` for every item before touching the adapter. See the "Authorization" section
  in the module documentation.

  ## Parameters

  * `items` (list): A list of structs, each representing an entity to be deleted. The list must contain items that have an `id` field.
  * `assigns` (map): The current assigns of the socket. Passed to `c:Backpex.LiveResource.can?/3`.
  * `live_resource` (module): The `Backpex.LiveResource` module.
  * `opts` (keyword list): A list of options:
    * `:authorization_action` (optional, default `:delete`): The action to authorize against.
    * `:authorize?` (optional, default `true`): Set to `false` to skip authorization.
  """
  def delete_all(items, assigns, live_resource, opts \\ [])
      when is_list(items) and is_map(assigns) and not is_struct(assigns) and is_atom(live_resource) do
    ensure_supported!(live_resource, :delete)
    _opts = authorize_items!(items, assigns, live_resource, opts, :delete)

    adapter = live_resource.config(:adapter)

    case adapter.delete_all(items, live_resource) do
      {:ok, deleted_items} = result ->
        Enum.each(deleted_items, fn deleted_item ->
          broadcast({:ok, deleted_item}, "deleted", live_resource)
        end)

        result

      error ->
        error
    end
  end

  @doc """
  Inserts a new item into a repository with specific parameters and options. It takes a repo module, a changeset function, an item, parameters for the changeset function, and additional options.

  Authorizes `:new` with a `nil` item before the changeset is built. See the "Authorization" section
  in the module documentation.

  ## Parameters

  * `item` (struct): The Ecto schema struct.
  * `attrs` (map): A map of parameters that will be passed to the `changeset_function`.
  * `fields` (list): The fields for this insert.
  * `assigns` (map): The current assigns of the socket. Passed to `c:Backpex.LiveResource.can?/3` and to the changeset function.
  * `live_resource` (module): The `Backpex.LiveResource` module.
  * `opts` (keyword list): A list of options:
    * `:authorization_action` (optional, default `:new`): The action to authorize against.
    * `:authorize?` (optional, default `true`): Set to `false` to skip authorization.
    * `:before_save_fun` (optional): A function called with the change before the item is inserted, returning the
      change to insert. Pass it to call `c:Backpex.LiveResource.on_item_creating/2`.
    * `:after_save_fun` (optional): A function called with the inserted item, returning `{:ok, item}`.
    * All remaining options are passed to `change/6`.
  """
  def insert(item, attrs, fields, assigns, live_resource, opts \\ []) do
    ensure_supported!(live_resource, :insert)
    opts = authorize_item!(nil, assigns, live_resource, opts, :new)

    persist_item(item, attrs, fields, assigns, live_resource, opts, :insert, "created")
  end

  @doc """
  Handles the update of an existing item with specific parameters and options. It takes a repo module, a changeset function, an item, parameters for the changeset function, and additional options.

  Authorizes `:edit` with the given item before the changeset is built. See the "Authorization"
  section in the module documentation.

  ## Parameters

  * `item` (struct): The Ecto schema struct.
  * `attrs` (map): A map of parameters that will be passed to the `changeset_function`.
  * `fields` (list): The fields for this update.
  * `assigns` (map): The current assigns of the socket. Passed to `c:Backpex.LiveResource.can?/3` and to the changeset function.
  * `live_resource` (module): The `Backpex.LiveResource` module.
  * `opts` (keyword list): A list of options:
    * `:authorization_action` (optional, default `:edit`): The action to authorize against.
    * `:authorize?` (optional, default `true`): Set to `false` to skip authorization.
    * `:before_save_fun` (optional): A function called with the change before the item is updated, returning the
      change to update. Pass it to call `c:Backpex.LiveResource.on_item_updating/2`.
    * `:after_save_fun` (optional): A function called with the updated item, returning `{:ok, item}`.
    * All remaining options are passed to `change/6`.
  """
  def update(item, attrs, fields, assigns, live_resource, opts \\ []) do
    ensure_supported!(live_resource, :update)
    opts = authorize_item!(item, assigns, live_resource, opts, :edit)

    persist_item(item, attrs, fields, assigns, live_resource, opts, :update, "updated")
  end

  defp persist_item(item, attrs, fields, assigns, live_resource, opts, action, event_name) do
    {before_save_fun, opts} = Keyword.pop(opts, :before_save_fun, &Function.identity/1)
    {after_save_fun, opts} = Keyword.pop(opts, :after_save_fun, &{:ok, &1})

    adapter = live_resource.config(:adapter)

    item
    |> change(attrs, fields, assigns, live_resource, Keyword.put(opts, :action, action))
    |> before_save(before_save_fun)
    |> then(fn changeset ->
      if action == :insert, do: adapter.insert(changeset, live_resource), else: adapter.update(changeset, live_resource)
    end)
    |> after_save(after_save_fun)
    |> broadcast(event_name, live_resource)
  end

  @doc """
  Updates multiple items from a given repository and schema.
  Additionally broadcasts the corresponding event, when PubSub config is given.

  Authorizes `:edit` for every item before touching the adapter. See the "Authorization" section in
  the module documentation.

  ## Parameters

  * `items` (list): A list of structs, each representing an entity to be updated.
  * `changes` (map): The fields to set and their values, e.g. `%{deleted_at: now}`. A keyword list works, too. The
    fields are checked against the description of the resource and the values cast to their types.
  * `assigns` (map): The current assigns of the socket. Passed to `c:Backpex.LiveResource.can?/3`.
  * `live_resource` (module): The `Backpex.LiveResource` module.
  * `opts` (keyword list): A list of options:
    * `:event_name` (optional, default `"updated"`): The name to be used when broadcasting the event.
    * `:authorization_action` (optional, default `:edit`): The action to authorize against.
    * `:authorize?` (optional, default `true`): Set to `false` to skip authorization.
  """
  def update_all(items, changes, assigns, live_resource, opts \\ [])
      when is_list(items) and is_map(assigns) and not is_struct(assigns) and is_atom(live_resource) do
    ensure_supported!(live_resource, :update)
    opts = authorize_items!(items, assigns, live_resource, opts, :edit)

    event_name = Keyword.get(opts, :event_name, "updated")
    adapter = live_resource.config(:adapter)

    case adapter.update_all(items, cast_changes!(changes, live_resource), live_resource) do
      {:ok, _count} ->
        Enum.each(items, fn item -> broadcast({:ok, item}, event_name, live_resource) end)
        {:ok, items}

      _error ->
        :error
    end
  end

  # The changes of `update_all/5` as a map, with the values cast to the types of their fields.
  defp cast_changes!(changes, live_resource) when is_list(changes) do
    if Keyword.keyword?(changes) and changes |> Keyword.keys() |> Enum.any?(&(&1 in [:set, :inc, :push, :pull])) do
      raise ArgumentError, """
      expected the changes as a map of fields and values, e.g. %{deleted_at: now}, got: #{inspect(changes)}

      update_all/5 no longer takes the updates of Ecto.Repo.update_all/3, see the guide on upgrading to v0.24.
      """
    end

    changes |> Map.new() |> cast_changes!(live_resource)
  end

  defp cast_changes!(changes, live_resource) when is_map(changes) do
    %{fields: fields} = describe([], live_resource)

    Map.new(changes, fn {name, value} ->
      case Map.fetch(fields, name) do
        {:ok, %{type: type}} -> {name, cast_change!(type, name, value)}
        :error -> raise ArgumentError, "unknown field #{inspect(name)} in the changes of update_all/5"
      end
    end)
  end

  defp cast_change!(_type, _name, nil), do: nil

  defp cast_change!(type, name, value) do
    case Backpex.Expr.cast_value(type, value) do
      {:ok, value} -> value
      :error -> raise ArgumentError, "can't cast #{inspect(value)} to the type of #{inspect(name)} in update_all/5"
    end
  end

  # A write the adapter doesn't support never reaches it, whatever the authorization action, see
  # `c:Backpex.Adapter.supports?/2`.
  defp ensure_supported!(live_resource, feature) do
    adapter = live_resource.config(:adapter)

    if not supports?(adapter, live_resource, feature) do
      raise ArgumentError, "#{inspect(adapter)} doesn't support #{inspect(feature)}, see Backpex.Adapter.supports?/2"
    end
  end

  # Pops the authorization options and runs the gate for a single item. Returns the remaining opts,
  # so `:authorization_action` and `:authorize?` never reach `change/6`.
  defp authorize_item!(item, assigns, live_resource, opts, default_action) do
    {authorize?, authorization_action, opts} = pop_authorization_opts(opts, default_action)

    if authorize?, do: Authorization.authorize!(live_resource, assigns, authorization_action, item)

    opts
  end

  # Same as `authorize_item!/5`, but strict over a list of items.
  defp authorize_items!(items, assigns, live_resource, opts, default_action) do
    {authorize?, authorization_action, opts} = pop_authorization_opts(opts, default_action)

    if authorize?, do: Authorization.authorize_all!(live_resource, assigns, authorization_action, items)

    opts
  end

  defp pop_authorization_opts(opts, default_action) do
    {authorize?, opts} = Keyword.pop(opts, :authorize?, true)
    {authorization_action, opts} = Keyword.pop(opts, :authorization_action, default_action)

    if !is_boolean(authorize?) do
      raise ArgumentError, "expected :authorize? to be a boolean, got: #{inspect(authorize?)}"
    end

    # `Keyword.pop/3` returns an explicitly passed `nil` rather than the default, and `nil` is an
    # atom — so an unvalidated `authorization_action: nil` would reach `can?(assigns, nil, item)`,
    # where a permissive catch-all clause silently authorizes the mutation. Refuse it here.
    if is_nil(authorization_action) or not is_atom(authorization_action) do
      raise ArgumentError,
            "expected :authorization_action to be a non-nil atom, got: #{inspect(authorization_action)}"
    end

    {authorize?, authorization_action, opts}
  end

  @doc """
  Applies a change to a given item by calling the specified changeset function.
  In addition, puts the given assocs into the function and calls the `c:Backpex.Field.before_changeset/5` callback for each field.

  ## Parameters

  * `item`: The initial data structure to be changed.
  * `attrs`: A map of attributes that will be used to modify the item. These attributes are passed to the changeset function.
  * `fields`: The fields for this change.
  * `assigns`: The assigns that will be passed to the changeset function.
  * `live_resource`: The `Backpex.LiveResource` to be used.
  * `opts` (keyword list): A list of options for customizing the behavior of the change function. The available options are:
    * `assocs` (optional, default `[]`): A list of associations that should be put into the changeset.
    * `target` (optional, default `nil`): The target to be passed to the changeset function.
    * `action` (optional, default `:validate`): An atom indicating the action to be performed on the changeset.
  """
  def change(item, attrs, fields, assigns, live_resource, opts \\ []) do
    adapter = live_resource.config(:adapter)

    adapter.change(item, attrs, fields, assigns, live_resource, opts)
  end

  @doc """
  Puts the associated items `value` into the association `name` of the changeset.
  """
  def put_assoc(changeset, name, value, live_resource) do
    adapter = live_resource.config(:adapter)

    adapter.put_assoc(changeset, name, value, live_resource)
  end

  @doc """
  Builds metadata passed to changeset functions.

  TODO: move?

  ## Parameters

  * `assigns`: The assigns that will be passed to the changeset function.
  * `target` (optional, default `nil`): The target to be passed to the changeset function.
  """
  def build_changeset_metadata(assigns, target \\ nil) do
    Keyword.new()
    |> Keyword.put(:assigns, assigns)
    |> Keyword.put(:target, target)
  end

  # A struct must come back as the same struct, so a hook that returns the socket, as `on_item_updated/2` does, or the
  # item instead of the change fails here instead of being saved.
  defp before_save(change, func) do
    case {change, func.(change)} do
      {%module{}, %module{} = result} ->
        result

      {%module{}, result} ->
        raise ArgumentError, """
        expected the function called before saving to return a #{inspect(module)}, got: #{inspect(result)}

        on_item_creating/2 and on_item_updating/2 must return the change they receive.
        """

      {_change, result} ->
        result
    end
  end

  defp after_save({:ok, item}, func) do
    {:ok, _item} = func.(item)
  end

  defp after_save(error, _func), do: error

  @doc """
  Broadcasts `event` on the `live_resource` topic in case `result` contains `{:ok, item}`.
  """
  def broadcast({:ok, item} = result, event, live_resource) do
    [server: pubsub, topic: topic] = live_resource.pubsub()

    Phoenix.PubSub.broadcast(pubsub, topic, {event, item})
    Phoenix.PubSub.broadcast(pubsub, topic, {"backpex:" <> event, item})

    result
  end

  def broadcast(result, _event, _opts), do: result
end
