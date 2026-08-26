defmodule Backpex.Resource do
  @moduledoc """
  Generic context module for Backpex resources.

  > ### Work in progress {: .warning}
  >
  > This module is still under heavy development and will change as we progress with the `Backpex.Adapter`
  > implementation in the coming releases. Keep this in mind when using this module directly.

  ## Authorization

  All mutations in this module are authorized through `Backpex.Authorization` before anything else
  happens — before the changeset is built and before `c:Backpex.Field.before_changeset/6` runs. An
  unauthorized call raises `Backpex.ForbiddenError` and never reaches the adapter.

  Each mutation has a default authorization action:

  | function | action | item passed to `c:Backpex.LiveResource.can?/3` |
  | --- | --- | --- |
  | `insert/6` | `:new` | `nil` |
  | `update/6` | `:edit` | the item |
  | `update_all/5` | `:edit` | each item |
  | `delete_all/4` | `:delete` | each item |

  Two options control this on every mutation:

  * `:authorization_action` (atom) — authorize against this action instead of the default. Item
    actions should pass `assigns.item_action_key` so a custom registration key is honored.
  * `:authorize?` (boolean, default `true`) — set to `false` to skip the check entirely. This is the
    escape hatch for system or cascade writes that are not a user-initiated action on that resource,
    for example nullifying foreign keys on another resource.

  Both options are consumed here and never reach `change/6`.

  For lists (`update_all/5`, `delete_all/4`) the check is strict: a single unauthorized item makes
  the whole call raise. A `nil` entry (a stale or forged item id) raises `Backpex.NoResultsError`.
  An empty list passes without calling the adapter's authorization.

  Reads (`list/4`, `get/4`, `get!/4`, `count/4`) are **not** authorized here. `:index` and `:show`
  remain enforced in the view layer — filtering rows after pagination would corrupt counts and
  select-all.
  """

  alias Backpex.Authorization

  @doc """
  Returns a list of items by given criteria.

  Example criteria:

  [
    order: %{by: :item, direction: :asc},
    pagination: %{page: 1, size: 5},
    search: {"hello", [:title, :description]}
  ]
  """
  def list(criteria, fields, assigns, live_resource) do
    adapter = live_resource.config(:adapter)

    adapter.list(criteria, fields, assigns, live_resource)
  end

  @doc """
  Gets the total count of the current live_resource.
  Possibly being constrained the item query and the search- and filter options.
  """
  def count(criteria, fields, assigns, live_resource) do
    adapter = live_resource.config(:adapter)

    adapter.count(criteria, fields, assigns, live_resource)
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
    adapter = live_resource.config(:adapter)

    adapter.get(primary_value, fields, assigns, live_resource)
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
  Deletes multiple items.
  Additionally broadcasts the corresponding event for each deleted item.

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
      when is_list(items) and is_map(assigns) and is_atom(live_resource) do
    _opts = authorize_items!(items, assigns, live_resource, opts, :delete)

    adapter = live_resource.config(:adapter)

    adapter.delete_all(items, live_resource)
    |> tap(fn {:ok, delete_items} ->
      Enum.each(delete_items, fn deleted_item ->
        broadcast({:ok, deleted_item}, "deleted", live_resource)
      end)
    end)
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
    * `:after_save_fun` (optional): A function called with the inserted item, returning `{:ok, item}`.
    * All remaining options are passed to `change/6`.
  """
  def insert(item, attrs, fields, assigns, live_resource, opts \\ []) do
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
    * `:after_save_fun` (optional): A function called with the updated item, returning `{:ok, item}`.
    * All remaining options are passed to `change/6`.
  """
  def update(item, attrs, fields, assigns, live_resource, opts \\ []) do
    opts = authorize_item!(item, assigns, live_resource, opts, :edit)

    persist_item(item, attrs, fields, assigns, live_resource, opts, :update, "updated")
  end

  defp persist_item(item, attrs, fields, assigns, live_resource, opts, action, event_name) do
    {after_save_fun, opts} = Keyword.pop(opts, :after_save_fun, &{:ok, &1})

    adapter = live_resource.config(:adapter)

    item
    |> change(attrs, fields, assigns, live_resource, Keyword.put(opts, :action, action))
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
  * `updates` (list): A list of updates passed to Ecto `update_all` function.
  * `assigns` (map): The current assigns of the socket. Passed to `c:Backpex.LiveResource.can?/3`.
  * `live_resource` (module): The `Backpex.LiveResource` module.
  * `opts` (keyword list): A list of options:
    * `:event_name` (optional, default `"updated"`): The name to be used when broadcasting the event.
    * `:authorization_action` (optional, default `:edit`): The action to authorize against.
    * `:authorize?` (optional, default `true`): Set to `false` to skip authorization.
  """
  def update_all(items, updates, assigns, live_resource, opts \\ [])
      when is_list(items) and is_map(assigns) and is_atom(live_resource) do
    opts = authorize_items!(items, assigns, live_resource, opts, :edit)

    event_name = Keyword.get(opts, :event_name, "updated")
    adapter = live_resource.config(:adapter)

    case adapter.update_all(items, updates, live_resource) do
      {_count_, nil} ->
        Enum.each(items, fn item -> broadcast({:ok, item}, event_name, live_resource) end)
        {:ok, items}

      _error ->
        :error
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

    {authorize?, authorization_action, opts}
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
