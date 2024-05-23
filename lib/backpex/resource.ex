defmodule Backpex.Resource do
  @moduledoc """
  Generic context module for Backpex resources.
  """
  import Ecto.Query

  alias Backpex.LiveResource

  @doc """
  Returns a list of items by given criteria.

  Example criteria:

  [
    order: %{by: :item, direction: :asc},
    pagination: %{page: 1, size: 5},
    search: {"hello", [:title, :description]}
  ]
  """
  def list(assigns, item_query, fields, criteria \\ []) do
    list_query(assigns, item_query, fields, criteria)
    |> assigns.repo.all()
  end

  @doc """
  Returns the main database query for selecting a list of items by given criteria.
  """
  def list_query(assigns, item_query, fields, criteria \\ []) do
    %{schema: schema, full_text_search: full_text_search, live_resource: live_resource} = assigns

    associations = associations(fields, schema)

    schema
    |> from(as: ^name_by_schema(schema))
    |> item_query.()
    |> maybe_join(associations)
    |> maybe_preload(associations, fields)
    |> maybe_merge_dynamic_fields(fields)
    |> apply_search(schema, full_text_search, criteria[:search])
    |> apply_filters(criteria[:filters], live_resource.get_empty_filter_key())
    |> apply_criteria(criteria, fields)
  end

  def metric_data(assigns, select, item_query, fields, criteria \\ []) do
    %{repo: repo, schema: schema, full_text_search: full_text_search, live_resource: live_resource} = assigns

    associations = associations(fields, schema)

    schema
    |> from(as: ^name_by_schema(schema))
    |> item_query.()
    |> maybe_join(associations)
    |> maybe_preload(associations, fields)
    |> apply_search(schema, full_text_search, criteria[:search])
    |> apply_filters(criteria[:filters], live_resource.get_empty_filter_key())
    |> select(^select)
    |> repo.one()
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

  defp maybe_join(query, []), do: query

  defp maybe_join(query, associations) do
    Enum.reduce(associations, query, fn
      %{queryable: queryable, owner_key: owner_key, cardinality: :one} = association, query ->
        custom_alias = Map.get(association, :custom_alias, name_by_schema(queryable))

        from(item in query,
          left_join: b in ^queryable,
          as: ^custom_alias,
          on: field(item, ^owner_key) == b.id
        )

      _relation, query ->
        query
    end)
  end

  def apply_search(query, _schema, nil, {_search_string, []}), do: query

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

  def apply_filters(query, [], _empty_filter_key), do: query

  def apply_filters(query, filters, empty_filter_key) do
    Enum.reduce(filters, query, fn
      %{field: ^empty_filter_key} = _filter, acc ->
        acc

      %{field: field, value: value, filter_config: filter_config} = _filter, acc ->
        filter_config.module.query(acc, field, value)
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

  defp get_custom_alias(fields, field_name, default_alias) do
    case Keyword.get(fields, field_name) do
      %{custom_alias: custom_alias} ->
        custom_alias

      _field_or_nil ->
        default_alias
    end
  end

  @doc """
  Gets the total count of the current live_resource.
  Possibly being constrained the item query and the search- and filter options.
  """
  def count(assigns, item_query, fields, search_options, filter_options) do
    %{
      repo: repo,
      schema: schema,
      full_text_search: full_text_search,
      live_resource: live_resource
    } = assigns

    associations = associations(fields, schema)

    from(schema, as: ^name_by_schema(schema))
    |> item_query.()
    |> maybe_join(associations)
    |> apply_search(schema, full_text_search, search_options)
    |> apply_filters(filter_options, live_resource.get_empty_filter_key())
    |> exclude(:preload)
    |> subquery()
    |> repo.aggregate(:count, :id)
  end

  @doc """
  Gets a database record with the given fields by the given id.

  ## Parameters

  - `id`: The identifier for the specific item to be fetched.
  - `repo` (module): The repository module.
  - `schema`: The Ecto schema module corresponding to the item
  - `item_query`: A function that modifies the base query. This function should accept an Ecto.Queryable and return an Ecto.Queryable. It's used to apply additional query logic.
  - `fields` (list): A list of atoms representing the fields to be selected and potentially preloaded.
  """
  def get(id, repo, schema, item_query, fields) do
    schema_name = name_by_schema(schema)
    associations = associations(fields, schema)

    from(item in schema, as: ^schema_name, distinct: item.id)
    |> item_query.()
    |> maybe_join(associations)
    |> maybe_preload(associations, fields)
    |> maybe_merge_dynamic_fields(fields)
    |> where([{^schema_name, schema_name}], schema_name.id == ^id)
    |> repo.one()
  end

  @doc """
  Deletes the given record from the database.
  Additionally broadcasts the corresponding event, when PubSub config is given.

  ## Parameters

  - `item` (struct): The item to be deleted.
  - `repo` (module): The repository module.
  - `pubsub` (map, default: `nil`): The PubSub config to use for broadcasting events.
  """
  def delete(item, repo, pubsub \\ nil) do
    item
    |> repo.delete()
    |> broadcast("deleted", pubsub)
  end

  @doc """
  Deletes multiple items from a given repository and schema.
  Additionally broadcasts the corresponding event, when PubSub config is given.

  ## Parameters

  - `items` (list): A list of structs, each representing an entity to be deleted. The list must contain items that have an `id` field.
  - `repo` (module): The repository module.
  - `schema` (module): The Ecto schema module corresponding to the entities in `items`.
  - `pubsub` (map, default: `nil`): The PubSub config to use for broadcasting events.
  """
  def delete_all(items, repo, schema, pubsub \\ nil) do
    case schema
         |> where([i], i.id in ^Enum.map(items, & &1.id))
         |> repo.delete_all() do
      {_count_, nil} ->
        Enum.each(items, fn item -> broadcast({:ok, item}, "deleted", pubsub) end)
        {:ok, items}

      _error ->
        :error
    end
  end

  @doc """
  Handles the update of an existing item with specific parameters and options. It takes a repo module, a changeset function, an item, parameters for the changeset function, and additional options.

  ## Parameters

  - `item` (struct): The Ecto schema struct.
  - `attrs` (map): A map of parameters that will be passed to the `changeset_function`.
  - `repo` (module): The repository module.
  - `changeset_function` (function): The function that transforms the item and parameters into a changeset.
  - `opts` (keyword list): A list of options for customizing the behavior of the insert function. The available options are:
    - `:assigns` (map, default: `%{}`): The assigns that will be passed to the changeset function.
    - `:pubsub` (map, default: `nil`): The PubSub config to use for broadcasting events.
    - `:assocs` (list, default: `[]`): A list of associations.
    - `:after_save` (function, default: `&{:ok, &1}`): A function to handle operations after the save.
  """
  def update(item, attrs, repo, changeset_function, opts) do
    assigns = Keyword.get(opts, :assigns, %{})
    pubsub = Keyword.get(opts, :pubsub, nil)
    assocs = Keyword.get(opts, :assocs, [])
    after_save = Keyword.get(opts, :after_save, &{:ok, &1})

    item
    |> change(attrs, changeset_function, assigns, assocs, nil, :update)
    |> repo.update()
    |> after_save(after_save)
    |> broadcast("updated", pubsub)
  end

  @doc """
  Updates multiple items from a given repository and schema.
  Additionally broadcasts the corresponding event, when PubSub config is given.

  ## Parameters

  - `items` (list): A list of structs, each representing an entity to be updated.
  - `repo` (module): The repository module.
  - `schema` (module): The Ecto schema module corresponding to the entities in `items`.
  - `updates` (list): A list of updates passed to Ecto `update_all` function.
  - `event_name` (string, default: `updated`): The name to be used when broadcasting the event.
  - `pubsub` (map, default: `nil`): The PubSub config to use for broadcasting events.
  """
  def update_all(items, repo, schema, updates, event_name \\ "updated", pubsub \\ nil) do
    case schema
         |> where([i], i.id in ^Enum.map(items, & &1.id))
         |> repo.update_all(updates) do
      {_count_, nil} ->
        Enum.each(items, fn item -> broadcast({:ok, item}, event_name, pubsub) end)
        {:ok, items}

      _error ->
        :error
    end
  end

  @doc """
  Inserts a new item into a repository with specific parameters and options. It takes a repo module, a changeset function, an item, parameters for the changeset function, and additional options.

  ## Parameters

  - `item` (struct): The Ecto schema struct.
  - `attrs` (map): A map of parameters that will be passed to the `changeset_function`.
  - `repo` (module): The repository module.
  - `changeset_function` (function): The function that transforms the item and parameters into a changeset.
  - `opts` (keyword list): A list of options for customizing the behavior of the insert function. The available options are:
    - `:assigns` (map, default: `%{}`): The assigns that will be passed to the changeset function.
    - `:pubsub` (map, default: `nil`): The PubSub config to use for broadcasting events.
    - `:assocs` (list, default: `[]`): A list of associations.
    - `:after_save` (function, default: `&{:ok, &1}`): A function to handle operations after the save.
  """
  def insert(item, attrs, repo, changeset_function, opts) do
    assigns = Keyword.get(opts, :assigns, %{})
    pubsub = Keyword.get(opts, :pubsub, nil)
    assocs = Keyword.get(opts, :assocs, [])
    after_save = Keyword.get(opts, :after_save, &{:ok, &1})

    item
    |> change(attrs, changeset_function, assigns, assocs, nil, :insert)
    |> repo.insert()
    |> after_save(after_save)
    |> broadcast("created", pubsub)
  end

  @doc """
  Applies a change to a given item by calling the specified changeset function.

  ## Parameters

  - `item`: The initial data structure to be changed.
  - `attrs`: A map of attributes that will be used to modify the item. These attributes are passed to the changeset function.
  - `changeset_function`: A function used to generate the changeset. This function is usually defined elsewhere in your codebase and should follow the changeset Ecto convention.
  - `assigns`: The assigns that will be passed to the changeset function.
  - `assocs` (optional, default `[]`): A list of associations that should be put into the changeset.
  - `target` (optional, default `nil`): The target to be passed to the changeset function.
  - `action` (optional, default `:validate`): An atom indicating the action to be performed on the changeset.
  """
  def change(item, attrs, changeset_function, assigns, assocs \\ [], target \\ nil, action \\ :validate) do
    item
    |> LiveResource.call_changeset_function(changeset_function, attrs, assigns, target)
    |> put_assocs(assocs)
    |> Map.put(:action, action)
  end

  @doc """
  Updates an Ecto changeset with a list of associations. It takes an existing changeset and a list of associations, and it updates the changeset with each association using `Ecto.Changeset.put_assoc/3`.

  ## Parameters

  - `changeset`: The changeset that you want to update with new associations.
  - `assocs` (keyword): A keyword list of associations to be added to the changeset. Each element should be a tuple with the association's key as the first element and the associated value as the second element.
  """
  def put_assocs(changeset, assocs) do
    Enum.reduce(assocs, changeset, fn {key, value}, acc ->
      Ecto.Changeset.put_assoc(acc, key, value)
    end)
  end

  @doc """
  Gets name by schema. This is the last part of the module name as a lowercase atom.

  ## Examples

      iex> Backpex.Resource.name_by_schema(Backpex.Resource)
      :resource
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

  defp after_save({:ok, item}, func) do
    {:ok, _item} = func.(item)
  end

  defp after_save(error, _func), do: error

  defp broadcast({:ok, item}, event, %{name: pubsub, topic: topic, event_prefix: event_prefix}) do
    Phoenix.PubSub.broadcast(pubsub, topic, {event_name(event_prefix, event), item})
    Phoenix.PubSub.broadcast(pubsub, topic, {"backpex:" <> event_name(event_prefix, event), item})

    {:ok, item}
  end

  defp broadcast({:error, _reason} = event, _event, _pubsub), do: event

  defp event_name(event_prefix, event), do: event_prefix <> event

  defp associations(fields, schema) do
    fields
    |> Enum.filter(fn {_name, field_options} = field -> field_options.module.association?(field) end)
    |> Enum.map(fn
      {name, %{custom_alias: custom_alias}} ->
        schema.__schema__(:association, name) |> Map.from_struct() |> Map.put(:custom_alias, custom_alias)

      {name, _field_options} ->
        schema.__schema__(:association, name) |> Map.from_struct()
    end)
  end
end
