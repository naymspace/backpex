defmodule Backpex.LiveResource.Show do
  @moduledoc false
  use BackpexWeb, :html

  import Phoenix.Component

  alias Backpex.LiveResource
  alias Backpex.Resource
  alias Backpex.Router
  alias Phoenix.LiveView

  require Backpex

  def mount(params, _session, socket, live_resource) do
    if LiveView.connected?(socket) do
      [server: server, topic: topic] = live_resource.pubsub()

      Phoenix.PubSub.subscribe(server, topic)
    end

    socket
    |> assign(:live_resource, live_resource)
    |> assign(:panels, live_resource.panels())
    |> assign(:fluid?, live_resource.config(:fluid?))
    |> assign(:page_title, live_resource.singular_name())
    |> assign(:selected_items, [])
    |> assign(:action_to_confirm, nil)
    |> assign(:params, params)
    |> assign_fields()
    |> assign_item()
    |> assign_item_actions()
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
    item = socket.assigns.item

    socket
    |> assign(selected_items: [item])
    |> maybe_handle_item_action(key)
    |> noreply()
  end

  def handle_event("cancel-action-confirm", _params, socket) do
    socket
    |> assign(:form_item, nil)
    |> assign(:changeset, nil)
    |> assign(:action_to_confirm, nil)
    |> noreply()
  end

  def handle_event(_event, _params, socket) do
    socket
    |> noreply()
  end

  def render(assigns) do
    Backpex.HTML.Resource.resource_show(assigns)
  end

  defp assign_item(socket) do
    %{live_resource: live_resource, params: params} = socket.assigns

    backpex_id = Map.fetch!(params, "backpex_id")
    primary_value = URI.decode(backpex_id)

    item = Resource.get!(primary_value, socket.assigns, live_resource)

    if not live_resource.can?(socket.assigns, :show, item), do: raise(Backpex.ForbiddenError)

    socket
    |> assign(:item, item)
    |> assign(:return_to, Router.get_path(socket, live_resource, params, :show, item))
  end

  defp assign_fields(socket) do
    fields =
      socket.assigns.live_resource.validated_fields()
      |> LiveResource.filtered_fields_by_action(socket.assigns, :show)

    assign(socket, :fields, fields)
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
      handle_item_action(socket, action, item)
    end
  end

  defp open_action_confirm_modal(socket, action, key) do
    if Backpex.ItemAction.has_form?(action) do
      changeset_function = &action.module.changeset/3
      base_schema = action.module.base_schema(socket.assigns)

      metadata = Resource.build_changeset_metadata(socket.assigns)
      changeset = changeset_function.(base_schema, %{}, metadata)

      socket
      |> assign(:form_item, base_schema)
      |> assign(:changeset, changeset)
    else
      assign(socket, :changeset, %{})
    end
    |> assign(:action_to_confirm, Map.put(action, :key, key))
  end

  defp handle_item_action(socket, action, item) do
    case action.module.handle(socket, [item], %{}) do
      {:ok, socket} ->
        socket
        |> assign(action_to_confirm: nil)
        |> assign(selected_items: [])
        |> assign(select_all: false)

      unexpected_return ->
        raise ArgumentError, """
        Invalid return value from #{inspect(action.module)}.handle/3.

        Expected: {:ok, socket}
        Got: #{inspect(unexpected_return)}

        Item Actions with no form fields must return {:ok, socket}.
        """
    end
  end
end
