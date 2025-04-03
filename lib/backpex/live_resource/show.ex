defmodule Backpex.LiveResource.Show do
  @moduledoc false

  alias Backpex.Utils
  alias Backpex.Resource
  alias Backpex.LiveResource
  alias Backpex.ResourceAction
  alias Backpex.Adapters.Ecto, as: EctoAdapter
  alias Backpex.Router
  alias Phoenix.LiveView
  use BackpexWeb, :html
  import Phoenix.Component
  require Backpex

  def mount(_params, _session, socket, index_live_resource) do
    live_resource = Utils.parent_module(index_live_resource)
    pubsub = live_resource.pubsub()
    LiveResource.subscribe_to_topic(socket, pubsub)

    socket
    |> assign(:live_resource, live_resource)
    |> assign(:panels, live_resource.panels())
    |> assign(:fluid?, live_resource.config(:fluid?))
    |> ok()
  end

  def handle_params(params, _url, socket) do
    socket
    |> assign(:params, params)
    |> apply_action(socket.assigns.live_action)
    |> noreply()
  end

  def render(assigns) do
    Backpex.HTML.Resource.resource_show(assigns)
  end

  defp apply_action(socket, :show) do
    %{live_resource: live_resource} = socket.assigns

    fields = live_resource.validated_fields() |> LiveResource.filtered_fields_by_action(socket.assigns, :show)
    primary_value = URI.decode(socket.assigns.params["backpex_id"])
    item = Resource.get!(primary_value, socket.assigns, live_resource)

    if not live_resource.can?(socket.assigns, :show, item), do: raise(Backpex.ForbiddenError)

    socket
    |> assign(:page_title, live_resource.singular_name())
    |> assign(:fields, fields)
    |> assign(:item, item)
    |> apply_show_return_to(item)
  end

  defp apply_show_return_to(socket, item) do
    %{live_resource: live_resource, params: params} = socket.assigns

    socket
    |> assign(:return_to, Router.get_path(socket, live_resource, params, :show, item))
  end
end
