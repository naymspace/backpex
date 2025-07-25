defmodule Backpex.Resource do
  @moduledoc """
  Generic context module for Backpex resources.

  > ### Work in progress {: .warning}
  >
  > This module is still under heavy development and will change as we progress with the `Backpex.Adapter`
  > implementation in the coming releases. Keep this in mind when using this module directly.
  """

  @doc """
  Returns a list of items by given criteria.

  Example criteria:

  [
    order: %{by: :item, direction: :asc},
    pagination: %{page: 1, size: 5},
    search: {"hello", [:title, :description]}
  ]
  """
  def list(criteria, assigns, live_resource) do
    adapter = live_resource.config(:adapter)

    adapter.list(criteria, assigns, live_resource)
  end

  @doc """
  Gets the total count of the current live_resource.
  Possibly being constrained the item query and the search- and filter options.
  """
  def count(criteria, assigns, live_resource) do
    adapter = live_resource.config(:adapter)

    adapter.count(criteria, assigns, live_resource)
  end

  @doc """
  Gets a database record with the given `fields` by the given  `primary_value`.

  Returns `{:ok, nil}` if no result was found.

  ## Parameters

  * `primary_value`: The identifier for the specific item to be fetched.
  * `assigns` (map): The current assigns of the socket.
  * `live_resource` (module): The `Backpex.LiveResource` module.
  """
  def get(primary_value, assigns, live_resource) do
    adapter = live_resource.config(:adapter)

    adapter.get(primary_value, assigns, live_resource)
  end

  @doc """
  Same as `get/3` but returns the result or raises an error.
  """
  def get!(primary_value, assigns, live_resource) do
    case get(primary_value, assigns, live_resource) do
      {:ok, nil} -> raise Backpex.NoResultsError
      {:ok, result} -> result
      {:error, _error} -> raise Backpex.NoResultsError
    end
  end

  @doc """
  Deletes multiple items.
  Additionally broadcasts the corresponding event for each deleted item.

  ## Parameters

  * `items` (list): A list of structs, each representing an entity to be deleted. The list must contain items that have an `id` field.
  * `live_resource` (module): The `Backpex.LiveResource` module.
  """
  def delete_all(items, live_resource) do
    adapter = live_resource.config(:adapter)

    items
    |> adapter.delete_all(live_resource)
    |> tap(fn {:ok, delete_items} ->
      Enum.each(delete_items, fn deleted_item ->
        broadcast({:ok, deleted_item}, "deleted", live_resource)
      end)
    end)
  end

  @doc """
  Inserts a new item into a repository with specific parameters and options. It takes a repo module, a changeset function, an item, parameters for the changeset function, and additional options.

  ## Parameters

  * `item` (struct): The Ecto schema struct.
  * `attrs` (map): A map of parameters that will be passed to the `changeset_function`.
  * TODO: docs
  """
  def insert(item, attrs, assigns, live_resource, opts) do
    {after_save_fun, opts} = Keyword.pop(opts, :after_save_fun, &{:ok, &1})

    adapter = live_resource.config(:adapter)
    fields = live_resource.validated_fields()

    item
    |> change(attrs, fields, assigns, live_resource, Keyword.put(opts, :action, :insert))
    |> adapter.insert(live_resource)
    |> after_save(after_save_fun)
    |> broadcast("created", live_resource)
  end

  @doc """
  Handles the update of an existing item with specific parameters and options. It takes a repo module, a changeset function, an item, parameters for the changeset function, and additional options.

  ## Parameters

  * `item` (struct): The Ecto schema struct.
  * `attrs` (map): A map of parameters that will be passed to the `changeset_function`.
  * TODO: docs
  """
  def update(item, attrs, fields, assigns, live_resource, opts \\ []) do
    {after_save_fun, opts} = Keyword.pop(opts, :after_save_fun, &{:ok, &1})

    adapter = live_resource.config(:adapter)

    item
    |> change(attrs, fields, assigns, live_resource, Keyword.put(opts, :action, :update))
    |> adapter.update(live_resource)
    |> after_save(after_save_fun)
    |> broadcast("updated", live_resource)
  end

  @doc """
  Updates multiple items from a given repository and schema.
  Additionally broadcasts the corresponding event, when PubSub config is given.

  ## Parameters

  * `items` (list): A list of structs, each representing an entity to be updated.
  * `updates` (list): A list of updates passed to Ecto `update_all` function.
  * `event_name` (string, default: `updated`): The name to be used when broadcasting the event.
  * `live_resource` (module): The `Backpex.LiveResource` module.
  """
  def update_all(items, updates, event_name \\ "updated", live_resource) do
    adapter = live_resource.config(:adapter)

    case adapter.update_all(items, updates, live_resource) do
      {_count_, nil} ->
        Enum.each(items, fn item -> broadcast({:ok, item}, event_name, live_resource) end)
        {:ok, items}

      _error ->
        :error
    end
  end

  @doc """
  Applies a change to a given item by calling the specified changeset function.
  In addition, puts the given assocs into the function and calls the `c:Backpex.Field.before_changeset/6` callback for each field.

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
