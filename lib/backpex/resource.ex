defmodule Backpex.Resource do
  @moduledoc """
  Generic context module for Backpex resources.
  """
  import Ecto.Query
  import Backpex.Adapters.Ecto, only: [name_by_schema: 1]
  alias Backpex.Ecto.EctoUtils
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
  def list(criteria \\ [], fields, assigns, live_resource) do
    adapter = live_resource.config(:adapter)
    adapter_config = live_resource.config(:adapter_config)

    adapter.list(criteria, fields, assigns, adapter_config)
  end

  def metric_data(assigns, select, item_query, fields, criteria \\ []) do
    %{repo: repo, schema: schema, full_text_search: full_text_search, live_resource: live_resource} = assigns

    associations = associations(fields, schema)

    schema
    |> from(as: ^name_by_schema(schema))
    |> item_query.()
    |> maybe_join(associations)
    |> maybe_preload(associations, fields)
    |> Backpex.Adapters.Ecto.apply_search(schema, full_text_search, criteria[:search])
    |> Backpex.Adapters.Ecto.apply_filters(criteria[:filters], live_resource.get_empty_filter_key())
    |> select(^select)
    |> repo.one()
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

        if has_named_binding?(query, custom_alias) do
          query
        else
          from(item in query,
            left_join: b in ^queryable,
            as: ^custom_alias,
            on: field(item, ^owner_key) == field(b, ^EctoUtils.get_primary_key_field(queryable))
          )
        end

      _relation, query ->
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
    |> Backpex.Adapters.Ecto.apply_search(schema, full_text_search, search_options)
    |> Backpex.Adapters.Ecto.apply_filters(filter_options, live_resource.get_empty_filter_key())
    |> exclude(:preload)
    |> subquery()
    |> repo.aggregate(:count)
  end

  @doc """
  Gets a database record with the given `fields` by the given  `primary_key_value`.

  Raises `Ecto.NoResultsError` if no record was found.

  ## Parameters

  * `primary_key_value`: The identifier for the specific item to be fetched.
  * `fields` (list): A list of atoms representing the fields to be selected and potentially preloaded.
  * `assigns` (map): The current assigns of the socket.
  * `live_resource` (module): The `Backpex.LiveResource` module.
  """
  def get!(primary_key_value, fields, assigns, live_resource) do
    adapter = live_resource.config(:adapter)
    adapter_config = live_resource.config(:adapter_config)

    adapter.get!(primary_key_value, fields, assigns, adapter_config)
  end

  @doc """
  Gets a database record with the given `fields` by the given  `primary_key_value`.

  Returns `nil` if no result was found.

  ## Parameters

  * `primary_key_value`: The identifier for the specific item to be fetched.
  * `fields` (list): A list of atoms representing the fields to be selected and potentially preloaded.
  * `assigns` (map): The current assigns of the socket.
  * `live_resource` (module): The `Backpex.LiveResource` module.
  """
  def get(primary_key_value, fields, assigns, live_resource) do
    adapter = live_resource.config(:adapter)
    adapter_config = live_resource.config(:adapter_config)

    adapter.get!(primary_key_value, fields, assigns, adapter_config)
  end

  @doc """
  Deletes the given record from the database.
  Additionally broadcasts the corresponding event, when PubSub config is given.

  ## Parameters

  * `item` (struct): The item to be deleted.
  * `repo` (module): The repository module.
  * `pubsub` (map, default: `nil`): The PubSub config to use for broadcasting events.
  """
  def delete(item, repo, pubsub \\ nil) do
    item
    |> repo.delete()
    |> broadcast("deleted", pubsub)
  end

  @doc """
  Deletes multiple items.
  Additionally broadcasts the corresponding event, when PubSub config is given.

  ## Parameters

  * `items` (list): A list of structs, each representing an entity to be deleted. The list must contain items that have an `id` field.
  * `live_resource` (module): The `Backpex.LiveResource` module.
  """
  def delete_all(items, live_resource) do
    adapter = live_resource.config(:adapter)
    adapter_config = live_resource.config(:adapter_config)
    pubsub = live_resource.config(:pubsub)

    case adapter.delete_all(items, adapter_config) do
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

  * `item` (struct): The Ecto schema struct.
  * `attrs` (map): A map of parameters that will be passed to the `changeset_function`.
  * `repo` (module): The repository module.
  * `fields` (keyword): The keyword list of fields defined in the live resource.
  * `changeset_function` (function): The function that transforms the item and parameters into a changeset.
  * `opts` (keyword list): A list of options for customizing the behavior of the insert function. The available options are:
    * `:assigns` (map, default: `%{}`): The assigns that will be passed to the changeset function.
    * `:pubsub` (map, default: `nil`): The PubSub config to use for broadcasting events.
    * `:assocs` (list, default: `[]`): A list of associations.
    * `:after_save` (function, default: `&{:ok, &1}`): A function to handle operations after the save.
  """
  def update(item, attrs, repo, fields, changeset_function, opts) do
    assigns = Keyword.get(opts, :assigns, %{})
    pubsub = Keyword.get(opts, :pubsub, nil)
    assocs = Keyword.get(opts, :assocs, [])
    after_save = Keyword.get(opts, :after_save, &{:ok, &1})

    item
    |> change(attrs, changeset_function, repo, fields, assigns, assocs: assocs, action: :update)
    |> repo.update()
    |> after_save(after_save)
    |> broadcast("updated", pubsub)
  end

  @doc """
  Updates multiple items from a given repository and schema.
  Additionally broadcasts the corresponding event, when PubSub config is given.

  ## Parameters

  * `items` (list): A list of structs, each representing an entity to be updated.
  * `repo` (module): The repository module.
  * `schema` (module): The Ecto schema module corresponding to the entities in `items`.
  * `updates` (list): A list of updates passed to Ecto `update_all` function.
  * `event_name` (string, default: `updated`): The name to be used when broadcasting the event.
  * `pubsub` (map, default: `nil`): The PubSub config to use for broadcasting events.
  """
  def update_all(items, repo, schema, updates, event_name \\ "updated", pubsub \\ nil) do
    id_field = EctoUtils.get_primary_key_field(schema)

    case schema
         |> where([i], field(i, ^id_field) in ^Enum.map(items, &Map.get(&1, id_field)))
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

  * `item` (struct): The Ecto schema struct.
  * `attrs` (map): A map of parameters that will be passed to the `changeset_function`.
  * `repo` (module): The repository module.
  * `fields` (keyword): The keyword list of fields defined in the live resource.
  * `changeset_function` (function): The function that transforms the item and parameters into a changeset.
  * `opts` (keyword list): A list of options for customizing the behavior of the insert function. The available options are:
    * `:assigns` (map, default: `%{}`): The assigns that will be passed to the changeset function.
    * `:pubsub` (map, default: `nil`): The PubSub config to use for broadcasting events.
    * `:assocs` (list, default: `[]`): A list of associations.
    * `:after_save` (function, default: `&{:ok, &1}`): A function to handle operations after the save.
  """
  def insert(item, attrs, repo, fields, changeset_function, opts) do
    assigns = Keyword.get(opts, :assigns, %{})
    pubsub = Keyword.get(opts, :pubsub, nil)
    assocs = Keyword.get(opts, :assocs, [])
    after_save = Keyword.get(opts, :after_save, &{:ok, &1})

    item
    |> change(attrs, changeset_function, repo, fields, assigns, assocs: assocs, action: :insert)
    |> repo.insert()
    |> after_save(after_save)
    |> broadcast("created", pubsub)
  end

  @doc """
  Applies a change to a given item by calling the specified changeset function.
  In addition, puts the given assocs into the function and calls the `c:Backpex.Field.before_changeset/6` callback for each field.

  ## Parameters

  * `item`: The initial data structure to be changed.
  * `attrs`: A map of attributes that will be used to modify the item. These attributes are passed to the changeset function.
  * `changeset_function`: A function used to generate the changeset. This function is usually defined elsewhere in your codebase and should follow the changeset Ecto convention.
  * `assigns`: The assigns that will be passed to the changeset function.
  * `opts` (keyword list): A list of options for customizing the behavior of the change function. The available options are:
    * `assocs` (optional, default `[]`): A list of associations that should be put into the changeset.
    * `target` (optional, default `nil`): The target to be passed to the changeset function.
    * `action` (optional, default `:validate`): An atom indicating the action to be performed on the changeset.
  """
  def change(item, attrs, changeset_function, repo, fields, assigns, opts \\ []) do
    assocs = Keyword.get(opts, :assocs, [])
    target = Keyword.get(opts, :target, nil)
    action = Keyword.get(opts, :action, :validate)
    metadata = build_changeset_metadata(assigns, target)

    item
    |> Ecto.Changeset.change()
    |> before_changesets(attrs, metadata, repo, fields, assigns)
    |> put_assocs(assocs)
    |> LiveResource.call_changeset_function(changeset_function, attrs, metadata)
    |> Map.put(:action, action)
  end

  def before_changesets(changeset, attrs, metadata, repo, fields, assigns) do
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
  Builds metadata passed to changeset functions.

  ## Parameters

  * `assigns`: The assigns that will be passed to the changeset function.
  * `target` (optional, default `nil`): The target to be passed to the changeset function.
  """
  def build_changeset_metadata(assigns, target \\ nil) do
    Keyword.new()
    |> Keyword.put(:assigns, assigns)
    |> Keyword.put(:target, target)
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

  defp broadcast(result, _event, _pubsub), do: result

  defp event_name(event_prefix, event), do: event_prefix <> event

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
          #{if without_id != name_str,
            do: """
            You are using a field ending with _id. Please make sure to use the correct field name for the association. Try using the name of the association, maybe "#{without_id}"?
            """,
            else: ""}.
          """
        end

        case field_options do
          %{custom_alias: custom_alias} ->
            association |> Map.from_struct() |> Map.put(:custom_alias, custom_alias)

          _ ->
            association |> Map.from_struct()
        end
    end)
  end
end
