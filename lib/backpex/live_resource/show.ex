defmodule Backpex.LiveResource.Show do
  @moduledoc false
  use BackpexWeb, :html

  import Phoenix.LiveView

  alias Backpex.Resource
  alias Backpex.Router

  require Backpex

  def mount(params, _session, socket, live_resource) do
    socket
    |> Backpex.LiveResource.maybe_subscribe_to_pubsub(live_resource)
    |> assign(:live_resource, live_resource)
    |> assign(:panels, live_resource.panels())
    |> assign(:fluid?, live_resource.config(:fluid?))
    |> assign(:fields, live_resource.fields(:show, socket.assigns))
    |> assign(:page_title, live_resource.singular_name())
    |> assign(:selected_items, [])
    |> assign(:action_to_confirm, nil)
    |> assign(:params, params)
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
    noreply(socket)
  end

  def render(assigns) do
    Backpex.HTML.Resource.resource_show(assigns)
  end

  defp assign_item(socket) do
    %{live_resource: live_resource, fields: fields, params: params} = socket.assigns
    backpex_id = Map.fetch!(params, "backpex_id")
    primary_value = URI.decode(backpex_id)

    case Resource.get(primary_value, fields, socket.assigns, live_resource) do
      {:ok, %{} = item} ->
        if not live_resource.can?(socket.assigns, :show, item), do: raise(Backpex.ForbiddenError)

        socket
        |> assign(:item, item)
        |> assign(:return_to, Router.get_path(socket, live_resource, params, :show, item))

      _item ->
        socket
        |> put_flash(:error, "The resource does not exist.")
        |> push_navigate(to: Router.get_path(socket, live_resource, params, :index))
    end
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
    if_result =
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

    if_result
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
