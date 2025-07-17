defmodule Backpex.LiveResource.Show do
  @moduledoc false
  use BackpexWeb, :html

  import Phoenix.Component

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
    |> assign(:fields, live_resource.fields(:show, socket.assigns))
    |> assign(:page_title, live_resource.singular_name())
    |> assign(:params, params)
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

  def handle_event(_event, _params, socket) do
    noreply(socket)
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
end
