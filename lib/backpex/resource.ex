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

            preload_query =
              queryable
              |> from(as: ^name_by_schema(queryable))
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
      %{queryable: queryable, owner_key: owner_key, cardinality: :one}, query ->
        from(item in query,
          left_join: b in ^queryable,
          as: ^name_by_schema(queryable),
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
    schema_name = name_by_schema(queryable)

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
      {:order, %{by: by, direction: direction, schema: schema}}, query ->
        schema_name = name_by_schema(schema)

        direction =
          case direction do
            :desc -> :desc_nulls_last
            :asc -> :asc_nulls_first
          end

        field =
          Enum.find(fields, fn
            {^by, field} -> field
            {_name, %{display_field: ^by} = field} -> field
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
    |> then(&repo.aggregate(subquery(&1), :count, :id))
  end

  @doc """
  Gets a database record with the given fields by the given id, possibly being enhanced by the given item_query.
  """
  def get(assigns, item_query, fields, id) do
    %{
      repo: repo,
      schema: schema
    } = assigns

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
  Additionally broadcasts the corresponding event, when PubSub is enabled.
  """
  def delete(assigns, item) do
    item
    |> assigns.repo.delete()
    |> broadcast("deleted", assigns)
  end

  @doc """
  Deletes the given records from the database.
  Additionally broadcasts the corresponding event, when PubSub is enabled.
  """
  def delete_all(assigns, items) do
    case assigns.schema
         |> where([i], i.id in ^Enum.map(items, & &1.id))
         |> assigns.repo.delete_all() do
      {_count_, nil} ->
        Enum.each(items, fn item -> broadcast({:ok, item}, "deleted", assigns) end)
        {:ok, items}

      _error ->
        :error
    end
  end

  @doc """
  Tries to update the current item with the given changes.
  Additionally broadcasts the corresponding event, when PubSub is enabled.
  """
  def update(assigns, change) do
    %{
      changeset: changeset,
      changeset_function: changeset_function,
      repo: repo
    } = assigns

    changeset
    |> prepare_for_validation()
    |> LiveResource.call_changeset_function(changeset_function, change)
    |> repo.update()
    |> broadcast("updated", assigns)
  end

  @doc """
  Tries to update many items with the given changes.
  Additionally broadcasts the corresponding event, when PubSub is enabled.
  """
  def update_all(assigns, items, updates, event \\ "updated") do
    case assigns.schema
         |> where([i], i.id in ^Enum.map(items, & &1.id))
         |> assigns.repo.update_all(updates) do
      {_count_, nil} ->
        Enum.each(items, fn item -> broadcast({:ok, item}, event, assigns) end)
        {:ok, items}

      _error ->
        :error
    end
  end

  @doc """
  Tries to insert the given changes as a new item for the current resource.
  Additionally broadcasts the corresponding event, when PubSub is enabled.
  """
  def insert(assigns, change) do
    %{
      changeset: changeset,
      changeset_function: changeset_function,
      repo: repo
    } = assigns

    changeset
    |> prepare_for_validation()
    |> LiveResource.call_changeset_function(changeset_function, change)
    |> repo.insert()
    |> broadcast("created", assigns)
  end

  defp prepare_for_validation(changeset) do
    changeset
    |> Map.put(:action, nil)
    |> Map.put(:errors, [])
    |> Map.put(:valid?, true)
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
    |> String.to_atom()
  end

  defp broadcast({:ok, item}, event, %{pubsub: %{name: pubsub, topic: topic, event_prefix: event_prefix}}) do
    Phoenix.PubSub.broadcast(pubsub, topic, {event_name(event_prefix, event), item})
    Phoenix.PubSub.broadcast(pubsub, topic, {"backpex:" <> event_name(event_prefix, event), item})

    {:ok, item}
  end

  defp broadcast({:error, _reason} = event, _event, _assigns), do: event

  defp event_name(event_prefix, event), do: event_prefix <> event

  defp associations(fields, schema) do
    fields
    |> Enum.filter(fn {_name, field_options} = field -> field_options.module.association?(field) end)
    |> Enum.map(fn {name, _field_options} ->
      schema.__schema__(:association, name) |> Map.from_struct()
    end)
  end
end
