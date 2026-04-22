defmodule Backpex.LiveResource.Show do
  @moduledoc false
  use BackpexWeb, :html

  import Phoenix.Component

  alias Backpex.Resource
  alias Backpex.Router

  def mount(params, _session, socket, live_resource) do
    socket
    |> Backpex.LiveResource.maybe_subscribe_to_pubsub(live_resource)
    |> assign(:live_resource, live_resource)
    |> assign(:panels, live_resource.panels())
    |> assign(:fluid?, live_resource.config(:fluid?))
    |> assign(:fields, live_resource.fields(:show, socket.assigns))
    |> assign(:page_title, live_resource.singular_name())
    |> assign(:params, params)
    |> assign_item_actions()
    |> assign_item()
    |> ok()
  end

  def handle_params(_params, _url, socket) do
    noreply(socket)
  end

  def handle_info({"backpex:updated", _item}, socket) do
    socket
    |> assign_item()
    |> noreply()
  end

  def handle_info(_event, socket) do
    noreply(socket)
  end

  def handle_event("item-action", %{"action-key" => key}, socket) do
    maybe_handle_item_action(socket, key)
  end

  def handle_event("cancel-action-confirm", _params, socket) do
    socket
    |> assign_item()
    |> assign(:changeset, nil)
    |> assign(:action_to_confirm, nil)
    |> noreply()
  end

  def handle_event(_event, _params, socket) do
    noreply(socket)
  end

  def render(assigns) do
    Backpex.HTML.Resource.resource_show(assigns)
  end

  defp assign_item(socket) do
    %{live_resource: live_resource, fields: fields, params: params} = socket.assigns
    backpex_id = Map.fetch!(params, "backpex_id")
    primary_value = URI.decode(backpex_id)
    item = Resource.get!(primary_value, fields, socket.assigns, live_resource)

    if not live_resource.can?(socket.assigns, :show, item), do: raise(Backpex.ForbiddenError)

    socket
    |> assign(:item, item)
    |> assign(:return_to, Router.get_path(socket, live_resource, params, :show, item))
  end

  defp assign_item_actions(socket) do
    item_actions = Backpex.ItemAction.default_actions() |> socket.assigns.live_resource.item_actions()
    assign(socket, :item_actions, item_actions)
  end

  defp maybe_handle_item_action(socket, key) do
    key = String.to_existing_atom(key)
    action = socket.assigns.item_actions[key]
    item = socket.assigns.item

    if Backpex.ItemAction.has_confirm_modal?(action) do
      open_action_confirm_modal(socket, action, key)
    else
      handle_item_action(socket, action, key, item)
    end
  end

  defp open_action_confirm_modal(socket, action, key) do
    %{item: item, live_resource: live_resource, params: params} = socket.assigns
    index_path = Router.get_path(socket, live_resource, params, :index)

    socket
    |> assign(:selected_items, [item])
    |> Backpex.ItemAction.assign_action_changeset(action)
    |> assign(:return_to, index_path)
    |> assign(:action_to_confirm, Map.put(action, :key, key))
    |> noreply()
  end

  defp handle_item_action(socket, action, key, item) do
    %{live_resource: live_resource, params: params} = socket.assigns
    index_path = Router.get_path(socket, live_resource, params, :index)

    Backpex.ItemAction.handle_item_action(socket, action, key, [item], fn socket ->
      socket
      |> assign(action_to_confirm: nil)
      |> maybe_navigate(index_path)
      |> noreply()
    end)
  end

  defp maybe_navigate(%{redirected: nil} = socket, path) do
    Phoenix.LiveView.push_navigate(socket, to: path)
  end

  defp maybe_navigate(socket, _path), do: socket
end
