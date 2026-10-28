# quokka:skip-module-directive-reordering
defmodule Backpex.Adapters.Ecto do
  @config_schema [
    repo: [
      doc: "The `Ecto.Repo` that will be used to perform CRUD operations for the given schema.",
      type: :atom,
      required: true
    ],
    schema: [
      doc: "The `Ecto.Schema` for the resource.",
      type: :atom,
      required: true
    ],
    update_changeset: [
      doc: """
      Changeset to use when updating items. Additional metadata is passed as a keyword list via the third parameter:
      - `:assigns` - the assigns
      - `:target` - the name of the `form` target that triggered the changeset call. Default to `nil` if the call was not triggered by a form field.
      """,
      type: {:fun, 3},
      default: &__MODULE__.default_changeset/3
    ],
    create_changeset: [
      doc: """
      Changeset to use when creating items. Additional metadata is passed as a keyword list via the third parameter:
      - `:assigns` - the assigns
      - `:target` - the name of the `form` target that triggered the changeset call. Default to `nil` if the call was not triggered by a form field.
      """,
      type: {:fun, 3},
      default: &__MODULE__.default_changeset/3
    ],
    item_query: [
      doc: """
      The function that can be used to modify the ecto query. It will be used when resources are being fetched. This
      happens on `index`, `edit` and `show` view. In most cases this function will be used to filter items on `index`
      view based on certain criteria, but it may also be used to join other tables on `edit` or `show` view.

      This function should accept the following parameters:

      - `query` - `Ecto.Query.t()`
      - `live_action` - `atom()`
      - `assigns` - `map()`

      It should return an `Ecto.Queryable`. It is recommended to build your `item_query` on top of the incoming query.
      Otherwise you will likely get binding errors.
      """,
      type: {:fun, 3},
      default: &__MODULE__.default_item_query/3
    ]
  ]

  @field_config_schema [
    select: [
      doc: """
      A dynamic query expression that selects the value of the field.

      ### Example

          full_name: %{
            module: Backpex.Fields.Text,
            label: "Full Name",
            select: dynamic([user: u], fragment("concat(?, ' ', ?)", u.first_name, u.last_name)),
          }
      """,
      type: {:struct, Ecto.Query.DynamicExpr}
    ],
    custom_alias: [
      doc: """
      The name of the binding of the association of the field in queries. Also see the
      [custom alias](/guides/fields/custom-alias.md) guide.
      """,
      type: :atom
    ]
  ]

  @moduledoc """
  The `Backpex.Adapter` to connect your `Backpex.LiveResource` to an `Ecto.Schema`.

  It builds and runs all queries of a LiveResource. It turns the expressions of filters and metrics (see
  `Backpex.Expr`) into `where` clauses, and the aggregates of metrics (see `Backpex.Metric`) into aggregate functions.

  ## Expressions

  The adapter checks the fields of expressions and casts their values with `Backpex.Resource.cast_expr/2` and its
  `describe/2`. Fields of an expression are fields of the schema. A path through relationships to one item, such as `author.name`,
  joins the relationships with left joins, which every expression with the same path shares. `exists/2` becomes a
  subquery of the primary keys of the items with a matching related item, so it doesn't duplicate items.
  `contains/2`, `starts_with/2` and `ends_with/2` become `like`, or `ilike` with `ignore_case: true`.

  `Backpex.Expr.native/2` takes an `Ecto.Query.dynamic/2` expression for this adapter, e.g. for a fragment of SQL. Its
  positional binding is the schema of the resource:

      Backpex.Expr.native(Backpex.Adapters.Ecto, dynamic([post], fragment("lower(?)", post.title) == ^title))

  These options and callbacks take Ecto queries, so only this adapter understands them:

    * the field options below and the `adapter_config` option `:item_query`
    * the `:options_query` option of association fields, which receives an `Ecto.Query`
    * the `:select` option of metrics, an `Ecto.Query.dynamic/2` expression to select instead of an aggregate
    * the callbacks of `Backpex.Adapters.Ecto.Field`

  ## Search

  Searchable fields are compared to the search string with `ilike`. Columns that are not strings, such as numbers or
  dates, are cast to text first. A field can build its own condition with
  `c:Backpex.Adapters.Ecto.Field.search_condition/3`.

  ## Field options

  This adapter adds these options to all fields:

  #{NimbleOptions.docs(@field_config_schema)}

  ## `adapter_config`

  #{NimbleOptions.docs(@config_schema)}

  > ### Work in progress {: .warning}
  >
  > The `Backpex.Adapters.Ecto` is still under development and may change in future updates.
  """

  use Backpex.Adapter, config_schema: @config_schema, field_config_schema: @field_config_schema
  import Ecto.Query

  alias Backpex.Adapters.Ecto.Where
  alias Backpex.Expr.Native
  alias Backpex.Expr.Ref
  alias Backpex.Query

  @doc false
  def default_changeset(item, attrs, _metadata), do: Ecto.Changeset.cast(item, attrs, [])

  @doc false
  def default_item_query(query, _live_action, _assigns), do: query

  @doc """
  Takes the options this adapter adds to fields (`:select` and `:custom_alias`), the `:options_query` of association
  fields and the callbacks of `Backpex.Adapters.Ecto.Field` into the query, see
  `c:Backpex.Adapter.put_field_options/2`.
  """
  @impl Backpex.Adapter
  def put_field_options(%Query{from: [], resource: live_resource} = query, {_name, field_options} = field) do
    schema = live_resource.adapter_config(:schema)
    ref = Backpex.LiveResource.field_ref(field)

    query =
      if field_options.module.association?(field) do
        association = fetch_association!(schema, field)
        put_association(query, association, field)
      else
        maybe_compute(query, field)
      end

    query
    |> update_native(:order_exprs, &Map.put(&1, ref, order_expr(field, schema)))
    |> update_native(:search_exprs, &Map.put(&1, ref, fn search -> search_condition(field, schema, search) end))
  end

  def put_field_options(%Query{from: [name], resource: live_resource} = query, {name, field_options} = field) do
    schema = live_resource.adapter_config(:schema)
    queryable = association_queryable(schema, field)
    display_field = Map.get(field_options, :display_field)

    assigns = Map.get(query.context, :assigns, %{})

    # A `:select` refers to the binding named after the schema, so the options query is named for it. Without it, the
    # binding is unnamed, as the options query of the field may name its own binding.
    {base, search_expr} =
      case Map.get(field_options, :select) do
        nil ->
          {from(queryable), fn search -> dynamic([option], ilike(field(option, ^display_field), ^search)) end}

        select ->
          {from(queryable, as: ^name_by_schema(queryable)), fn search -> dynamic(ilike(^select, ^search)) end}
      end

    query
    |> Query.put_native(:options_query, maybe_options_query(base, field_options, assigns))
    |> update_native(:search_exprs, &Map.put(&1, Backpex.Expr.ref(display_field), search_expr))
  end

  def put_field_options(%Query{} = query, _field), do: query

  defp update_native(query, key, fun), do: Query.put_native(query, key, fun.(Map.get(query.native, key, %{})))

  defp put_association(query, association, {name, field_options}) do
    association =
      case field_options do
        %{custom_alias: custom_alias} -> association |> Map.from_struct() |> Map.put(:custom_alias, custom_alias)
        _other -> Map.from_struct(association)
      end

    query
    |> update_native(:associations, &Map.put(&1, name, association))
    |> update_native(:preloads, &Map.put(&1, name, preload_select(association, field_options)))
  end

  defp preload_select(association, %{display_field: display_field, select: select}) do
    queryable = Map.get(association, :queryable)
    custom_alias = Map.get(association, :custom_alias, name_by_schema(queryable))

    queryable
    |> from(as: ^custom_alias)
    |> select_merge(^%{display_field => select})
  end

  defp preload_select(_association, _field_options), do: nil

  # A field with a `:select` and without a `:display_field` gets its value from the expression.
  defp maybe_compute(query, {name, %{select: select} = field_options})
       when not is_map_key(field_options, :display_field),
       do: Query.compute(query, name, Backpex.Expr.native(__MODULE__, select))

  defp maybe_compute(query, _field), do: query

  # The expression a field is ordered by: its `:select`, or the column it shows in the binding of its schema.
  defp order_expr({_name, %{select: select}}, _schema), do: {:select, select}

  defp order_expr(field, schema) do
    binding = binding_name(field, schema)
    %{name: column} = Backpex.LiveResource.field_ref(field)

    {:column, dynamic([{^binding, item}], field(item, ^column))}
  end

  @doc """
  Returns the items of the query, see `c:Backpex.Adapter.read/1`.
  """
  @impl Backpex.Adapter
  def read(%Query{resource: live_resource} = query) do
    repo = live_resource.adapter_config(:repo)

    query
    |> to_ecto_query()
    |> repo.all()
    |> then(fn items -> {:ok, items} end)
  end

  @doc """
  Returns the number of items of the query, see `c:Backpex.Adapter.count/1`.
  """
  @impl Backpex.Adapter
  def count(%Query{resource: live_resource} = query) do
    repo = live_resource.adapter_config(:repo)

    query
    |> to_ecto_query()
    |> exclude(:preload)
    |> exclude(:select)
    |> subquery()
    |> repo.aggregate(:count)
    |> then(fn count -> {:ok, count} end)
  end

  @doc """
  Returns the values of the aggregates of the query, see `c:Backpex.Adapter.aggregate/1`.

  An aggregate may be a `Backpex.Expr.native/2` expression of this adapter, an `Ecto.Query.dynamic/2` expression to
  select, usually an aggregate function. Each aggregate is computed with its own query.
  """
  @impl Backpex.Adapter
  def aggregate(%Query{resource: live_resource, aggregates: aggregates} = query) do
    repo = live_resource.adapter_config(:repo)

    base =
      query
      |> Query.unset([:aggregates])
      |> to_ecto_query()
      |> exclude(:select)
      |> exclude(:preload)
      |> exclude(:group_by)
      |> exclude(:order_by)

    {:ok,
     Map.new(aggregates, fn %{name: name, aggregate: aggregate, where: where} ->
       data =
         base
         |> Where.where_expr(where)
         |> select(^aggregate_dynamic(aggregate))
         |> repo.one()

       {name, data}
     end)}
  end

  # An aggregate, see `t:Backpex.Metric.aggregate/0`.
  defp aggregate_dynamic(%Native{adapter: __MODULE__, expr: expression}), do: expression
  defp aggregate_dynamic(:count), do: dynamic(count())
  defp aggregate_dynamic({:count, field}) when is_atom(field), do: dynamic([item], count(field(item, ^field)))
  defp aggregate_dynamic({:sum, field}) when is_atom(field), do: dynamic([item], sum(field(item, ^field)))
  defp aggregate_dynamic({:avg, field}) when is_atom(field), do: dynamic([item], avg(field(item, ^field)))
  defp aggregate_dynamic({:min, field}) when is_atom(field), do: dynamic([item], min(field(item, ^field)))
  defp aggregate_dynamic({:max, field}) when is_atom(field), do: dynamic([item], max(field(item, ^field)))

  defp aggregate_dynamic(aggregate) do
    raise ArgumentError, "expected an aggregate such as :count or {:sum, :field}, got: #{inspect(aggregate)}"
  end

  @doc """
  Returns a new struct of the schema.
  """
  @impl Backpex.Adapter
  def new_item(_assigns, live_resource) do
    struct(live_resource.adapter_config(:schema))
  end

  @doc """
  Returns the description of the schema of the resource, or of the schema at the end of the associations in `path`. See
  `c:Backpex.Adapter.describe/2`.
  """
  @impl Backpex.Adapter
  def describe(path, live_resource) do
    path
    |> Enum.reduce_while(live_resource.adapter_config(:schema), fn name, schema ->
      case schema.__schema__(:association, name) do
        nil -> {:halt, nil}
        association -> {:cont, related_schema(schema, association)}
      end
    end)
    |> describe_schema()
  end

  defp related_schema(_owner, %{related: related}), do: related

  defp related_schema(owner, %Ecto.Association.HasThrough{through: through}) do
    Enum.reduce(through, owner, fn name, schema -> related_schema(schema, schema.__schema__(:association, name)) end)
  end

  defp describe_schema(nil = _schema), do: nil

  defp describe_schema(schema) do
    %Backpex.Adapter.Description{
      primary_key: schema.__schema__(:primary_key),
      fields: :fields |> schema.__schema__() |> Map.new(&{&1, field_info(schema, &1)}),
      relationships: :associations |> schema.__schema__() |> Map.new(&{&1, association_info(schema, &1)})
    }
  end

  # The SQL adapters of Ecto store a `:binary_id` as a UUID, so values are cast with `Ecto.UUID`, which refuses other
  # strings instead of letting the database raise.
  defp field_info(schema, name) do
    type = schema.__schema__(:type, name)
    cast_type = if type == :binary_id, do: Ecto.UUID, else: type

    %{type: cast_type, primitive: Ecto.Type.type(type)}
  end

  defp association_info(owner, name) when is_atom(name),
    do: association_info(owner, owner.__schema__(:association, name))

  defp association_info(owner, association) do
    %{
      field: association.field,
      cardinality: association.cardinality,
      owner_key: association.owner_key,
      through: through_info(owner, association)
    }
  end

  defp through_info(owner, %Ecto.Association.HasThrough{through: through}) do
    {associations, _related} =
      Enum.map_reduce(through, owner, fn name, schema ->
        association = schema.__schema__(:association, name)

        {association_info(schema, association), related_queryable(schema, association)}
      end)

    associations
  end

  defp through_info(_owner, _association), do: []

  defp maybe_options_query(query, %{options_query: options_query}, assigns), do: options_query.(query, assigns)
  defp maybe_options_query(query, _field_options, _assigns), do: query

  defp search_condition({_name, %{select: select} = _field_options}, _schema, search_string) do
    dynamic(ilike(^select, ^search_string))
  end

  defp search_condition({name, field_options} = field, schema, search_string) do
    queryable = field_queryable(field, schema)
    field_name = Map.get(field_options, :display_field, name)
    schema_name = Map.get(field_options, :custom_alias, name_by_schema(queryable))

    if callback?(field_options.module, :search_condition, 3) do
      dynamic(^field_options.module.search_condition(schema_name, field_name, search_string))
    else
      field_options
      |> column_queryable(queryable, schema)
      |> default_search_condition(schema_name, field_name, search_string)
    end
  end

  # The schema of the resource doesn't describe the columns of a custom alias, e.g. of a join in the `item_query`.
  defp column_queryable(%{custom_alias: _custom_alias}, schema, schema), do: nil
  defp column_queryable(_field_options, queryable, _schema), do: queryable

  # PostgreSQL only supports `ilike` on text, so other columns are cast to text. A column of unknown type is cast as
  # well, as casting a text column to text changes nothing.
  defp default_search_condition(queryable, schema_name, field_name, search_string) do
    if string_field?(queryable, field_name) do
      dynamic([{^schema_name, schema_name}], ilike(field(schema_name, ^field_name), ^search_string))
    else
      dynamic(
        [{^schema_name, schema_name}],
        ilike(fragment("CAST(? AS TEXT)", field(schema_name, ^field_name)), ^search_string)
      )
    end
  end

  defp string_field?(nil = _queryable, _field_name), do: false

  defp string_field?(queryable, field_name) do
    case queryable.__schema__(:type, field_name) do
      nil -> false
      type -> Ecto.Type.type(type) == :string
    end
  end

  @doc """
  Deletes multiple items.
  """
  @impl Backpex.Adapter
  def delete_all(items, live_resource) do
    schema = live_resource.adapter_config(:schema)
    repo = live_resource.adapter_config(:repo)
    primary_key = live_resource.config(:primary_key)

    result =
      schema
      |> where([item], field(item, ^primary_key) in ^Enum.map(items, &Map.get(&1, primary_key)))
      |> select([item], item)
      |> repo.delete_all()

    case result do
      {_count, deleted_items} when is_list(deleted_items) ->
        {:ok, deleted_items}

      {_count, _deleted_items} ->
        {:ok, []}
    end
  rescue
    error ->
      if foreign_key_violation?(error), do: {:error, :foreign_key_violation}, else: reraise(error, __STACKTRACE__)
  end

  defp foreign_key_violation?(%Postgrex.Error{postgres: %{code: :foreign_key_violation}}), do: true
  defp foreign_key_violation?(%Ecto.ConstraintError{type: :foreign_key}), do: true
  defp foreign_key_violation?(_error), do: false

  @doc """
  Inserts given item.
  """
  @impl Backpex.Adapter
  def insert(item, live_resource) do
    repo = live_resource.adapter_config(:repo)

    repo.insert(item)
  end

  @doc """
  Updates given item.
  """
  @impl Backpex.Adapter
  def update(item, live_resource) do
    repo = live_resource.adapter_config(:repo)

    repo.update(item)
  end

  @doc """
  Updates given items.
  """
  @impl Backpex.Adapter
  def update_all(items, updates, live_resource) do
    repo = live_resource.adapter_config(:repo)
    schema = live_resource.adapter_config(:schema)
    primary_key = live_resource.config(:primary_key)

    schema
    |> where([i], field(i, ^primary_key) in ^Enum.map(items, &Map.get(&1, primary_key)))
    |> repo.update_all(updates)
  end

  @doc """
  Applies a change to a given item.
  """
  @impl Backpex.Adapter
  def change(item, attrs, fields, assigns, live_resource, opts) do
    assocs = Keyword.get(opts, :assocs, [])
    target = Keyword.get(opts, :target)
    action = Keyword.get(opts, :action, :validate)
    metadata = Backpex.Resource.build_changeset_metadata(assigns, target)
    changeset_function = get_changeset_function(assigns.live_action, live_resource, assigns)

    item
    |> Ecto.Changeset.change()
    |> before_changesets(attrs, metadata, fields, assigns)
    |> put_assocs(assocs)
    |> changeset_function.(attrs, metadata)
    |> Map.put(:action, action)
  end

  defp get_changeset_function(:new, live_resource, _assigns), do: live_resource.adapter_config(:create_changeset)
  defp get_changeset_function(:edit, live_resource, _assigns), do: live_resource.adapter_config(:update_changeset)
  # TODO: find solution for this workaround
  defp get_changeset_function(:index, live_resource, _assigns), do: live_resource.adapter_config(:update_changeset)
  defp get_changeset_function(:resource_action, _live_resource, assigns), do: assigns.changeset_function

  defp before_changesets(changeset, attrs, metadata, fields, assigns) do
    Enum.reduce(fields, changeset, fn {_name, field_options} = field, acc ->
      field_options.module.before_changeset(acc, attrs, metadata, field, assigns)
    end)
  end

  defp put_assocs(changeset, assocs) do
    Enum.reduce(assocs, changeset, fn {key, value}, acc ->
      Ecto.Changeset.put_assoc(acc, key, value)
    end)
  end

  @doc """
  Puts the associated items into the changeset with `Ecto.Changeset.put_assoc/4`.
  """
  @impl Backpex.Adapter
  def put_assoc(changeset, name, value, _live_resource) do
    Ecto.Changeset.put_assoc(changeset, name, value)
  end

  @doc """
  Gets name by schema. This is the last part of the module name as a lowercase atom.

  TODO: Make this private once all fields are using the adapter abstractions.
  """
  # sobelow_skip ["DOS.StringToAtom"]
  def name_by_schema(schema) do
    schema
    |> Module.split()
    |> List.last()
    |> String.downcase()
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    |> String.to_atom()
  end

  # --- PRIVATE

  defp fetch_association!(schema, {name, field_options} = _field) do
    with nil <- schema.__schema__(:association, name) do
      name_str = name |> Atom.to_string()
      without_id = String.replace(name_str, ~r/_id$/, "")

      raise """
      The field "#{name}"" is not an association but used as if it were one with the field module #{inspect(field_options.module)}.
      #{if without_id == name_str,
        do: "",
        else: """
        You are using a field ending with _id. Please make sure to use the correct field name for the association. Try using the name of the association, maybe "#{without_id}"?
        """}.
      """
    end
  end

  # The schema of the column a field shows. For an association field, this is the schema of the associated items.
  defp field_queryable({_name, %{module: module}} = field, schema) do
    cond do
      callback?(module, :schema, 2) -> module.schema(field, schema)
      module.association?(field) -> association_queryable(schema, field)
      true -> schema
    end
  end

  defp association_queryable(schema, field) do
    related_queryable(schema, fetch_association!(schema, field))
  end

  defp related_queryable(owner, %Ecto.Association.HasThrough{through: through}) do
    Enum.reduce(through, owner, fn name, schema -> related_queryable(schema, schema.__schema__(:association, name)) end)
  end

  defp related_queryable(_owner, %{queryable: queryable}), do: queryable

  # The named binding of the column a field shows, see `maybe_join/2`.
  defp binding_name({_name, %{custom_alias: custom_alias}}, _schema), do: custom_alias
  defp binding_name(field, schema), do: name_by_schema(field_queryable(field, schema))

  defp callback?(module, function, arity) do
    Code.ensure_loaded?(module) and function_exported?(module, function, arity)
  end

  defp maybe_join(query, []), do: query

  defp maybe_join(query, associations) do
    Enum.reduce(associations, query, fn
      %{queryable: queryable, owner_key: owner_key, cardinality: :one} = association, query ->
        custom_alias = Map.get(association, :custom_alias, name_by_schema(queryable))

        if has_named_binding?(query, custom_alias) do
          query
        else
          from(item in query,
            left_join: b in ^queryable,
            as: ^custom_alias,
            on: field(item, ^owner_key) == field(b, ^get_primary_key_field(queryable))
          )
        end

      _relation, query ->
        query
    end)
  end

  def get_primary_key_field(schema)

  def get_primary_key_field(%{__struct__: struct}) when is_atom(struct), do: get_primary_key_field(struct)

  def get_primary_key_field(module) when is_atom(module) do
    resolve_primary_key(&module.__schema__/1)
  end

  def get_primary_key_field(%{__schema__: schema_getter}) when is_function(schema_getter, 1) do
    resolve_primary_key(schema_getter)
  end

  defp resolve_primary_key(schema_getter) when is_function(schema_getter, 1) do
    case schema_getter.(:primary_key) do
      [id] -> id
      [] -> raise_no_primary_key_error()
      _multiple -> raise_compound_primary_key_error()
    end
  end

  defp raise_no_primary_key_error do
    raise ArgumentError, "No primary key found. Please define a primary key in your schema."
  end

  defp raise_compound_primary_key_error do
    raise ArgumentError, "Compound primary keys are not supported. Please use a single primary key."
  end

  defp maybe_preload(query, [], _preloads), do: query

  defp maybe_preload(query, load, preloads) do
    preload_items =
      Enum.map(load, fn name ->
        case Map.get(preloads, name) do
          nil -> name
          preload_query -> {name, preload_query}
        end
      end)

    preload(query, ^preload_items)
  end

  defp merge_computed(query, computed) do
    Enum.reduce(computed, query, fn
      {name, %Native{adapter: __MODULE__, expr: %Ecto.Query.DynamicExpr{} = expression}}, query ->
        select_merge(query, ^%{name => expression})

      {name, value}, _query ->
        raise ArgumentError,
              "expected the computed value #{inspect(name)} to be a native expression of #{inspect(__MODULE__)}, " <>
                "got: #{inspect(value)}"
    end)
  end

  # --- QUERIES

  @doc """
  Returns the `Ecto.Query` the adapter runs for the `Backpex.Query`, e.g. to stream the items of an export with
  `c:Ecto.Repo.stream/2`.
  """
  @spec ecto_query(Query.t()) :: Ecto.Query.t()
  def ecto_query(%Query{} = query), do: to_ecto_query(query)

  # The query of the items of the resource.
  defp to_ecto_query(%Query{from: []} = query) do
    %{resource: live_resource, native: native, context: context} = query
    schema = live_resource.adapter_config(:schema)
    item_query = live_resource.adapter_config(:item_query)
    assigns = Map.get(context, :assigns, %{})

    schema
    |> from(as: ^name_by_schema(schema))
    |> item_query.(Map.get(assigns, :live_action), assigns)
    |> maybe_join(native |> Map.get(:associations, %{}) |> Map.values())
    |> maybe_preload(query.load, Map.get(native, :preloads, %{}))
    |> merge_computed(query.computed)
    |> Where.where_expr(query.filter)
    |> apply_search(query, schema)
    |> apply_sorts(query, schema)
    |> apply_offset_limit(query)
  end

  # The query of related items, e.g. the options of an association field.
  defp to_ecto_query(%Query{from: path, resource: live_resource} = query) do
    queryable = path_queryable(live_resource.adapter_config(:schema), path)

    query.native
    |> Map.get_lazy(:options_query, fn -> from(queryable) end)
    |> Ecto.Queryable.to_query()
    |> maybe_preload(query.load, %{})
    |> Where.where_expr(query.filter)
    |> apply_search(query, queryable)
    |> apply_sorts(query, queryable)
    |> apply_offset_limit(query)
  end

  defp apply_search(ecto_query, %Query{search: nil}, _schema), do: ecto_query

  defp apply_search(ecto_query, %Query{from: [], search: %{term: term}, resource: live_resource} = query, schema) do
    case live_resource.config(:full_text_search) do
      nil ->
        search_targets(ecto_query, query, schema)

      full_text_search ->
        schema_name = name_by_schema(schema)

        where(
          ecto_query,
          [{^schema_name, schema_name}],
          fragment("? @@ websearch_to_tsquery(?)", field(schema_name, ^full_text_search), ^term)
        )
    end
  end

  defp apply_search(ecto_query, query, schema), do: search_targets(ecto_query, query, schema)

  # An item matches if any target contains the search term, ignoring the case.
  defp search_targets(ecto_query, %Query{search: %{targets: []}}, _schema), do: ecto_query

  defp search_targets(ecto_query, %Query{search: %{term: term, targets: targets}, native: native}, schema) do
    pattern = "%#{term}%"
    search_exprs = Map.get(native, :search_exprs, %{})

    {conditions, ecto_query} =
      Enum.map_reduce(targets, ecto_query, fn ref, ecto_query ->
        case Map.fetch(search_exprs, ref) do
          {:ok, search_expr} -> {search_expr.(pattern), ecto_query}
          :error -> ref_search(ecto_query, ref, schema, pattern)
        end
      end)

    condition = Enum.reduce(conditions, fn condition, acc -> dynamic(^acc or ^condition) end)

    where(ecto_query, ^condition)
  end

  # Searches the column of a ref, cast to text unless it is a string.
  defp ref_search(ecto_query, %Ref{path: path, name: name} = ref, schema, pattern) do
    {ecto_query, column} = Where.field(ecto_query, ref)

    if string_field?(path_queryable(schema, path), name),
      do: {dynamic(ilike(^column, ^pattern)), ecto_query},
      else: {dynamic(ilike(fragment("CAST(? AS TEXT)", ^column), ^pattern)), ecto_query}
  end

  defp path_queryable(schema, path) do
    Enum.reduce(path, schema, fn name, schema -> related_queryable(schema, fetch_association!(schema, {name, %{}})) end)
  end

  defp apply_sorts(ecto_query, %Query{native: native} = query, schema) do
    order_exprs = Map.get(native, :order_exprs, %{})

    query
    |> Query.sorts()
    |> Enum.reduce(ecto_query, fn {ref, direction}, ecto_query ->
      case Map.fetch(order_exprs, ref) do
        {:ok, {:select, expression}} ->
          order_by(ecto_query, ^[{direction, expression}])

        {:ok, {:column, expression}} ->
          order_by(ecto_query, ^[{column_direction(ref, direction, schema), expression}])

        :error ->
          {ecto_query, expression} = Where.field(ecto_query, ref)
          order_by(ecto_query, ^[{column_direction(ref, direction, schema), expression}])
      end
    end)
  end

  # A primary key is never NULL, so NULLS FIRST/LAST would only keep the database from using its index.
  defp column_direction(%Ref{path: [], name: name}, direction, schema) when is_atom(schema) do
    if name in schema.__schema__(:primary_key), do: without_nulls(direction), else: direction
  end

  defp column_direction(_ref, direction, _schema), do: direction

  defp without_nulls(direction) when direction in [:asc_nulls_first, :asc_nulls_last], do: :asc
  defp without_nulls(direction) when direction in [:desc_nulls_first, :desc_nulls_last], do: :desc
  defp without_nulls(direction), do: direction

  defp apply_offset_limit(ecto_query, %Query{offset: offset, limit: limit}) do
    ecto_query
    |> then(&if(offset, do: offset(&1, ^offset), else: &1))
    |> then(&if(limit, do: limit(&1, ^limit), else: &1))
  end
end
