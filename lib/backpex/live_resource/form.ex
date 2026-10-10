defmodule Backpex.LiveResource.Form do
  @moduledoc false
  use BackpexWeb, :html

  import Phoenix.Component

  alias Backpex.Authorization
  alias Backpex.LiveResource
  alias Backpex.Resource

  require Backpex

  def mount(params, _session, socket, live_resource) do
    live_action = socket.assigns.live_action

    socket
    |> assign(:live_resource, live_resource)
    |> assign(:panels, live_resource.panels())
    |> assign(:fluid?, live_resource.config(:fluid?))
    |> assign(:fields, live_resource.fields(live_action, socket.assigns))
    |> assign(:params, params)
    |> assign(:page_title, page_title(live_resource, live_action))
    |> assign_return_to(params)
    |> assign_item(live_action)
    |> can?(live_resource, live_action)
    |> assign_changeset(live_action)
    |> ok()
  end

  def handle_params(_params, _url, socket) do
    noreply(socket)
  end

  def render(assigns) do
    Backpex.HTML.Resource.resource_form(assigns)
  end

  # credo:disable-for-this-file Credo.Check.Design.DuplicatedCode
  def handle_info({:update_changeset, changeset}, socket) do
    socket
    |> assign(:changeset, changeset)
    |> noreply()
  end

  # credo:disable-for-this-file Credo.Check.Design.DuplicatedCode
  def handle_info({:put_assoc, {key, value} = _assoc}, socket) do
    changeset = Resource.put_assoc(socket.assigns.changeset, key, value, socket.assigns.live_resource)
    assocs = Map.get(socket.assigns, :assocs, []) |> Keyword.put(key, value)

    socket
    |> assign(:assocs, assocs)
    |> assign(:changeset, changeset)
    |> noreply()
  end

  def handle_info(_event, socket) do
    noreply(socket)
  end

  def handle_event(_event, _params, socket) do
    noreply(socket)
  end

  defp page_title(live_resource, :new = _live_action) do
    Backpex.__({"New %{resource}", %{resource: live_resource.singular_name()}}, live_resource)
  end

  defp page_title(live_resource, :edit = _live_action) do
    Backpex.__({"Edit %{resource}", %{resource: live_resource.singular_name()}}, live_resource)
  end

  defp assign_return_to(socket, params) do
    case LiveResource.return_to_param(params) do
      nil -> socket
      return_to -> assign(socket, :return_to, return_to)
    end
  end

  defp assign_item(socket, :new = _live_action) do
    assign(socket, :item, Resource.new_item(socket.assigns, socket.assigns.live_resource))
  end

  defp assign_item(socket, :edit = _live_action) do
    %{live_resource: live_resource, fields: fields, params: params} = socket.assigns

    backpex_id = Map.fetch!(params, "backpex_id")
    primary_value = URI.decode(backpex_id)

    item = Resource.get!(primary_value, fields, socket.assigns, live_resource)

    assign(socket, :item, item)
  end

  defp can?(socket, live_resource, :new = live_action) do
    Authorization.authorize!(live_resource, socket.assigns, live_action, nil)

    socket
  end

  defp can?(socket, live_resource, :edit = live_action) do
    Authorization.authorize!(live_resource, socket.assigns, live_action, socket.assigns.item)

    socket
  end

  # The adapter applies the changeset function of the live action. Without an action, the form doesn't show errors yet.
  defp assign_changeset(socket, live_action) do
    %{live_resource: live_resource, item: item, fields: fields} = socket.assigns

    attrs = LiveResource.default_attrs(live_action, fields, socket.assigns)
    changeset = Resource.change(item, attrs, fields, socket.assigns, live_resource, action: nil)

    assign(socket, :changeset, changeset)
  end
end
