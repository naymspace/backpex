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

  ## `adapter_config`

  #{NimbleOptions.docs(@config_schema)}

  > ### Work in progress {: .warning}
  >
  > The `Backpex.Adapters.Ecto` is under heavy development and will change drastically in future updates.
  > Backpex started out as `Ecto`-only and we are working on decoupling things to support multiple data sources.
  > This is the first draft of moving all `Ecto` related functions into a dedicated Ecto adapter.
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
    |> apply_filters(criteria[:filters], Backpex.LiveResource.empty_filter_key(), assigns)
    |> apply_criteria(criteria, fields)
  end

  def apply_search(query, _schema, nil, {_search_string, []}), do: query

  def apply_search(query, _schema, nil, {"", _searchable_fields}), do: query

  def apply_search(query, _schema, nil, {search_string, searchable_fields}) do
    search_string = "%#{search_string}%"

    conditions = search_conditions(searchable_fields, search_string)
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

  defp search_conditions([field], search_string) do
    search_condition(field, search_string)
  end

  defp search_conditions([field | searchable_fields], search_string) do
    dynamic(^search_condition(field, search_string) or ^search_conditions(searchable_fields, search_string))
  end

  defp search_condition({_name, %{select: select} = _field_options}, search_string) do
    dynamic(ilike(^select, ^search_string))
  end

  defp search_condition({name, %{queryable: queryable} = field_options}, search_string) do
    field_name = Map.get(field_options, :display_field, name)
    schema_name = Map.get(field_options, :custom_alias, name_by_schema(queryable))

    dynamic(^field_options.module.search_condition(schema_name, field_name, search_string))
  end

  def apply_filters(query, [], _empty_filter_key, _assigns), do: query

  def apply_filters(query, filters, empty_filter_key, assigns) do
    Enum.reduce(filters, query, fn
      %{field: ^empty_filter_key} = _filter, acc ->
        acc

      %{field: field, value: value, filter_config: filter_config} = _filter, acc ->
        filter_config.module.query(acc, field, value, assigns)
    end)
  end

  def apply_criteria(query, [], _fields), do: query

  def apply_criteria(query, criteria, fields) do
    Enum.reduce(criteria, query, fn
      {:order, %{by: by, direction: direction, schema: schema, field_name: field_name}}, query ->
        schema_name = get_custom_alias(fields, field_name, name_by_schema(schema))

        direction =
          case direction do
            :desc -> :desc_nulls_last
            :asc -> :asc_nulls_first
          end

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
  end

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
    target = Keyword.get(opts, :target, nil)
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
      {name, field_options} ->
        association = schema.__schema__(:association, name)

        if association == nil do
          name_str = name |> Atom.to_string()
          without_id = String.replace(name_str, ~r/_id$/, "")

          # credo:disable-for-lines:3 Credo.Check.Refactor.Nesting
          raise """
          The field "#{name}"" is not an association but used as if it were one with the field module #{inspect(field_options.module)}.
          #{if without_id == name_str,
            do: "",
            else: """
            You are using a field ending with _id. Please make sure to use the correct field name for the association. Try using the name of the association, maybe "#{without_id}"?
            """}.
          """
        end

        case field_options do
          %{custom_alias: custom_alias} ->
            association |> Map.from_struct() |> Map.put(:custom_alias, custom_alias)

          _other ->
            association |> Map.from_struct()
        end
    end)
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

  defp get_custom_alias(fields, field_name, default_alias) do
    case Keyword.get(fields, field_name) do
      %{custom_alias: custom_alias} -> custom_alias
      _field_or_nil -> default_alias
    end
  end
end
