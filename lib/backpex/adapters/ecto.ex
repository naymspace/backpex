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

  @moduledoc """
  The `Backpex.Adapter` to connect your `Backpex.LiveResource` to an `Ecto.Schema`.

  It builds and runs all queries of a LiveResource, directly or through the options and callbacks that take Ecto
  queries. Only this adapter calls them: the `:select` option of fields, the `:options_query` option of association
  fields, `c:Backpex.Field.search_condition/3`, `c:Backpex.Field.before_changeset/6`, `c:Backpex.Filter.query/4` and
  `c:Backpex.Metric.query/3`.

  ## Search

  Searchable fields are compared to the search string with `ilike`. Columns that are not strings, such as numbers or
  dates, are cast to text first. A field can build its own condition with `c:Backpex.Field.search_condition/3`.

  ## `adapter_config`

  #{NimbleOptions.docs(@config_schema)}

  > ### Work in progress {: .warning}
  >
  > The `Backpex.Adapters.Ecto` is still under development and may change in future updates.
  """

  use Backpex.Adapter, config_schema: @config_schema
  import Ecto.Query

  @doc false
  def default_changeset(item, attrs, _metadata), do: Ecto.Changeset.cast(item, attrs, [])

  @doc false
  def default_item_query(query, _live_action, _assigns), do: query

  @doc """
  Gets a database record with the given primary key value.
  """
  @impl Backpex.Adapter
  def get(primary_value, fields, assigns, live_resource) do
    repo = live_resource.adapter_config(:repo)

    record_query(primary_value, assigns, fields, live_resource)
    |> repo.one()
    |> then(fn result -> {:ok, result} end)
  end

  @doc """
  Returns a list of items by given criteria.
  """
  @impl Backpex.Adapter
  def list(criteria, fields, assigns, live_resource) do
    repo = live_resource.adapter_config(:repo)

    list_query(criteria, fields, assigns, live_resource)
    |> repo.all()
    |> then(fn items -> {:ok, items} end)
  end

  @doc """
  Returns the number of items matching the given criteria.
  """
  @impl Backpex.Adapter
  def count(criteria, fields, assigns, live_resource) do
    repo = live_resource.adapter_config(:repo)

    list_query(criteria, fields, assigns, live_resource)
    |> exclude(:preload)
    |> exclude(:select)
    |> subquery()
    |> repo.aggregate(:count)
    |> then(fn count -> {:ok, count} end)
  end

  @doc """
  Returns the data of a metric for the items matching the given criteria by calling the `c:Backpex.Metric.query/3`
  callback of the metric.
  """
  @impl Backpex.Adapter
  def metric(metric, criteria, fields, assigns, live_resource) do
    repo = live_resource.adapter_config(:repo)

    criteria
    |> list_query(fields, assigns, live_resource)
    |> exclude(:select)
    |> exclude(:preload)
    |> exclude(:group_by)
    |> metric.module.query(Map.get(metric, :select), repo)
    |> then(fn data -> {:ok, data} end)
  end

  @doc """
  Returns a new struct of the schema.
  """
  @impl Backpex.Adapter
  def new_item(_assigns, live_resource) do
    struct(live_resource.adapter_config(:schema))
  end

  @doc """
  Returns the association `name` of the schema.
  """
  @impl Backpex.Adapter
  def association(name, live_resource) do
    schema = live_resource.adapter_config(:schema)

    case schema.__schema__(:association, name) do
      nil -> nil
      association -> association_info(schema, association)
    end
  end

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

  @doc """
  Returns the items of the association of the field that can be selected, using the `:options_query` of the field.
  """
  @impl Backpex.Adapter
  def list_options(field, criteria, assigns, live_resource) do
    repo = live_resource.adapter_config(:repo)

    field
    |> options_query(criteria, assigns, live_resource)
    |> repo.all()
    |> then(fn items -> {:ok, items} end)
  end

  @doc """
  Same as `list_options/4` for many assigns at once. Runs each distinct query once.
  """
  @impl Backpex.Adapter
  def list_options_by_key(field, criteria, assigns_by_key, live_resource) do
    repo = live_resource.adapter_config(:repo)

    queries =
      Map.new(assigns_by_key, fn {key, assigns} -> {key, options_query(field, criteria, assigns, live_resource)} end)

    items_by_query = queries |> Map.values() |> Enum.uniq() |> Map.new(&{&1, repo.all(&1)})

    {:ok, Map.new(queries, fn {key, query} -> {key, Map.fetch!(items_by_query, query)} end)}
  end

  @doc """
  Returns the number of items `list_options/4` returns, ignoring `:offset` and `:limit`.
  """
  @impl Backpex.Adapter
  def count_options(field, criteria, assigns, live_resource) do
    repo = live_resource.adapter_config(:repo)

    field
    |> options_query(Keyword.drop(criteria, [:offset, :limit]), assigns, live_resource)
    |> subquery()
    |> repo.aggregate(:count)
    |> then(fn count -> {:ok, count} end)
  end

  defp options_query({_name, field_options} = field, criteria, assigns, live_resource) do
    queryable = association_queryable(live_resource.adapter_config(:schema), field)

    queryable
    |> options_base_query(criteria[:search])
    |> maybe_where_ids(queryable, Keyword.fetch(criteria, :ids))
    |> maybe_options_query(field_options, assigns)
    |> maybe_search_options(field, queryable, criteria[:search])
    |> maybe_offset(criteria[:offset])
    |> maybe_limit(criteria[:limit])
  end

  # The binding is only named for a search, as the options query of a field may name its own binding.
  defp options_base_query(queryable, nil = _search), do: from(queryable)
  defp options_base_query(queryable, _search), do: from(queryable, as: ^name_by_schema(queryable))

  defp maybe_where_ids(query, _queryable, :error), do: query

  defp maybe_where_ids(query, queryable, {:ok, ids}) do
    type = queryable.__schema__(:type, :id)

    ids =
      Enum.flat_map(ids, fn id ->
        case Ecto.Type.cast(type, id) do
          {:ok, id} -> [id]
          :error -> []
        end
      end)

    where(query, [option], option.id in ^ids)
  end

  defp maybe_options_query(query, %{options_query: options_query}, assigns), do: options_query.(query, assigns)
  defp maybe_options_query(query, _field_options, _assigns), do: query

  defp maybe_search_options(query, _field, _queryable, nil), do: query

  defp maybe_search_options(query, {_name, field_options} = field, queryable, search) do
    if String.trim(search) == "" do
      query
    else
      search = "%#{search}%"

      case Map.get(field_options, :select) do
        nil ->
          schema_name = name_by_schema(queryable)
          display_field = field_options.module.display_field(field)

          where(query, [{^schema_name, schema_name}], ilike(field(schema_name, ^display_field), ^search))

        select ->
          where(query, ^dynamic(ilike(^select, ^search)))
      end
    end
  end

  defp maybe_offset(query, nil), do: query
  defp maybe_offset(query, offset), do: offset(query, ^offset)

  defp maybe_limit(query, nil), do: query
  defp maybe_limit(query, limit), do: limit(query, ^limit)

  @doc """
  Returns the main database query for selecting a list of items by given criteria.

  TODO: Should be private.
  """
  def list_query(criteria, fields, assigns, live_resource) do
    schema = live_resource.adapter_config(:schema)
    item_query = live_resource.adapter_config(:item_query)
    full_text_search = live_resource.config(:full_text_search)
    associations = associations(fields, schema)

    schema
    |> from(as: ^name_by_schema(schema))
    |> item_query.(assigns.live_action, assigns)
    |> maybe_join(associations)
    |> maybe_preload(associations, fields)
    |> maybe_merge_dynamic_fields(fields)
    |> apply_search(schema, full_text_search, criteria[:search])
    |> apply_filters(criteria[:filter_values], criteria[:filter_configs], assigns)
    |> apply_criteria(criteria, fields, schema)
  end

  def apply_search(query, _schema, nil, {_search_string, []}), do: query

  def apply_search(query, _schema, nil, {"", _searchable_fields}), do: query

  def apply_search(query, schema, nil, {search_string, searchable_fields}) do
    search_string = "%#{search_string}%"

    conditions = search_conditions(searchable_fields, schema, search_string)
    where(query, ^conditions)
  end

  def apply_search(query, schema, full_text_search, {search_string, _searchable_fields}) do
    case search_string do
      "" ->
        query

      search ->
        schema_name = name_by_schema(schema)

        where(
          query,
          [{^schema_name, schema_name}],
          fragment("? @@ websearch_to_tsquery(?)", field(schema_name, ^full_text_search), ^search)
        )
    end
  end

  defp search_conditions([field], schema, search_string) do
    search_condition(field, schema, search_string)
  end

  defp search_conditions([field | searchable_fields], schema, search_string) do
    dynamic(
      ^search_condition(field, schema, search_string) or ^search_conditions(searchable_fields, schema, search_string)
    )
  end

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
      default_search_condition(queryable, schema_name, field_name, search_string)
    end
  end

  # PostgreSQL only supports `ilike` on text, so other columns are cast to text.
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

  # A column that is not part of the schema, e.g. of a join in the `item_query`, is compared as it is.
  defp string_field?(queryable, field_name) do
    case queryable.__schema__(:type, field_name) do
      nil -> true
      type -> Ecto.Type.type(type) == :string
    end
  end

  @doc """
  Applies validated filters to the query.

  Receives a map of validated filter values and the filter configurations keyword list.
  For each filter value, looks up the corresponding filter config and invokes
  the filter's query/4 callback with the already-validated and casted value.
  """
  def apply_filters(query, filter_values, filter_configs, assigns)
      when is_map(filter_values) and is_list(filter_configs) do
    Enum.reduce(filter_values, query, fn {field, value}, acc ->
      case Keyword.get(filter_configs, field) do
        nil -> acc
        filter_config -> filter_config.module.query(acc, field, value, assigns)
      end
    end)
  end

  def apply_filters(query, _filter_values, _filter_configs, _assigns), do: query

  def apply_criteria(query, [], _fields, _schema), do: query

  def apply_criteria(query, criteria, fields, schema) do
    Enum.reduce(criteria, query, fn
      {:order, order}, query ->
        apply_order(query, order, fields, schema)

      {:limit, limit}, query ->
        query
        |> limit(^limit)

      {:pagination, %{page: page, size: size}}, query ->
        query
        |> offset(^((page - 1) * size))
        |> limit(^size)

      _criteria, query ->
        query
    end)
  end

  defp apply_order(query, %{by: by, direction: direction} = order, fields, schema) do
    field_name = Map.get(order, :field_name)
    schema_name = binding_name(fields, field_name, schema)

    direction = order_direction(direction, Map.get(order, :nulls, :default))

    field =
      Enum.find(fields, fn
        {^by, field} -> field
        {^field_name, %{display_field: ^by} = field} -> field
        _field -> nil
      end)

    case field do
      {_name, %{select: select} = _field_options} ->
        query
        |> order_by([{^schema_name, schema_name}], ^[{direction, select}])

      _field ->
        query
        |> order_by([{^schema_name, schema_name}], [
          {^direction, field(schema_name, ^by)}
        ])
    end
  end

  defp apply_order(_query, order, _fields, _schema) do
    raise ArgumentError,
          "expected order criteria to be a map with the keys :by and :direction, got: #{inspect(order)}"
  end

  defp order_direction(direction, :default) when direction in [:asc, :desc], do: direction
  defp order_direction(:asc, :first), do: :asc_nulls_first
  defp order_direction(:asc, :last), do: :asc_nulls_last
  defp order_direction(:desc, :first), do: :desc_nulls_first
  defp order_direction(:desc, :last), do: :desc_nulls_last
  defp order_direction(:asc, :smallest), do: :asc_nulls_first
  defp order_direction(:desc, :smallest), do: :desc_nulls_last

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
    repo = live_resource.adapter_config(:repo)
    assocs = Keyword.get(opts, :assocs, [])
    target = Keyword.get(opts, :target)
    action = Keyword.get(opts, :action, :validate)
    metadata = Backpex.Resource.build_changeset_metadata(assigns, target)
    changeset_function = get_changeset_function(assigns.live_action, live_resource, assigns)

    item
    |> Ecto.Changeset.change()
    |> before_changesets(attrs, metadata, repo, fields, assigns)
    |> put_assocs(assocs)
    |> changeset_function.(attrs, metadata)
    |> Map.put(:action, action)
  end

  defp get_changeset_function(:new, live_resource, _assigns), do: live_resource.adapter_config(:create_changeset)
  defp get_changeset_function(:edit, live_resource, _assigns), do: live_resource.adapter_config(:update_changeset)
  # TODO: find solution for this workaround
  defp get_changeset_function(:index, live_resource, _assigns), do: live_resource.adapter_config(:update_changeset)
  defp get_changeset_function(:resource_action, _live_resource, assigns), do: assigns.changeset_function

  defp before_changesets(changeset, attrs, metadata, repo, fields, assigns) do
    Enum.reduce(fields, changeset, fn {_name, field_options} = field, acc ->
      field_options.module.before_changeset(acc, attrs, metadata, repo, field, assigns)
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

  defp record_query(primary_value, assigns, fields, live_resource) do
    schema = live_resource.adapter_config(:schema)
    item_query = live_resource.adapter_config(:item_query)
    schema_name = name_by_schema(schema)
    primary_key = live_resource.config(:primary_key)
    primary_type = schema.__schema__(:type, primary_key)
    associations = associations(fields, schema)

    from(item in schema, as: ^schema_name, distinct: field(item, ^primary_key))
    |> item_query.(assigns.live_action, assigns)
    |> maybe_join(associations)
    |> maybe_preload(associations, fields)
    |> maybe_merge_dynamic_fields(fields)
    |> where_id(schema_name, primary_key, primary_type, primary_value)
  end

  defp where_id(query, schema_name, id_field, :id, id) do
    case Ecto.Type.cast(:id, id) do
      {:ok, valid_id} -> where(query, [{^schema_name, schema_name}], field(schema_name, ^id_field) == ^valid_id)
      :error -> raise Ecto.NoResultsError, queryable: query
    end
  end

  defp where_id(query, schema_name, id_field, :binary_id, id) do
    case Ecto.UUID.cast(id) do
      {:ok, valid_id} -> where(query, [{^schema_name, schema_name}], field(schema_name, ^id_field) == ^valid_id)
      :error -> raise Ecto.NoResultsError, queryable: query
    end
  end

  defp where_id(query, schema_name, id_field, _id_type, id) do
    where(query, [{^schema_name, schema_name}], field(schema_name, ^id_field) == ^id)
  end

  defp associations(fields, schema) do
    fields
    |> Enum.filter(fn {_name, field_options} = field -> field_options.module.association?(field) end)
    |> Enum.map(fn
      {_name, field_options} = field ->
        association = fetch_association!(schema, field)

        case field_options do
          %{custom_alias: custom_alias} ->
            association |> Map.from_struct() |> Map.put(:custom_alias, custom_alias)

          _other ->
            association |> Map.from_struct()
        end
    end)
  end

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
  defp binding_name(fields, field_name, schema) do
    case List.keyfind(fields, field_name, 0) do
      {_name, %{custom_alias: custom_alias}} -> custom_alias
      nil -> name_by_schema(schema)
      field -> name_by_schema(field_queryable(field, schema))
    end
  end

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

  defp maybe_preload(query, [], _fields), do: query

  defp maybe_preload(query, associations, fields) do
    preload_items =
      Enum.map(associations, fn %{field: assoc_field} = association ->
        field = Enum.find(fields, fn {name, _field_options} -> name == assoc_field end)

        case field do
          {_name, %{display_field: display_field, select: select}} ->
            queryable = Map.get(association, :queryable)
            custom_alias = Map.get(association, :custom_alias, name_by_schema(queryable))

            preload_query =
              queryable
              |> from(as: ^custom_alias)
              |> select_merge(^%{display_field => select})

            {assoc_field, preload_query}

          _field ->
            assoc_field
        end
      end)

    query
    |> preload(^preload_items)
  end

  defp maybe_merge_dynamic_fields(query, fields) do
    fields
    |> Enum.reduce(query, fn
      {_name, %{display_field: _display_field}}, q ->
        q

      {name, %{select: select}}, q ->
        select_merge(q, ^%{name => select})

      _field, q ->
        q
    end)
  end
end
