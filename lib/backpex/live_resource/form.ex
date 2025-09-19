defmodule Backpex.LiveResource.Form do
  @moduledoc false
  use BackpexWeb, :html

  import Phoenix.Component

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
    changeset = Ecto.Changeset.put_assoc(socket.assigns.changeset, key, value)
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

  defp assign_item(socket, :new = _live_action) do
    schema = socket.assigns.live_resource.adapter_config(:schema)
    empty_item = schema.__struct__()

    assign(socket, :item, empty_item)
  end

  defp assign_item(socket, :edit = _live_action) do
    %{live_resource: live_resource, fields: fields, params: params} = socket.assigns

    backpex_id = Map.fetch!(params, "backpex_id")
    primary_value = URI.decode(backpex_id)

    item = Resource.get!(primary_value, fields, socket.assigns, live_resource)

    assign(socket, :item, item)
  end

  defp can?(socket, live_resource, :new = live_action) do
    if not live_resource.can?(socket.assigns, live_action, nil), do: raise(Backpex.ForbiddenError)

    socket
  end

  defp can?(socket, live_resource, :edit = live_action) do
    if not live_resource.can?(socket.assigns, live_action, socket.assigns.item), do: raise(Backpex.ForbiddenError)

    socket
  end

  defp assign_changeset(socket, live_action) do
    %{live_resource: live_resource, item: item, fields: fields} = socket.assigns

    changeset_fun = changeset_fun(live_resource, live_action)
    LiveResource.assign_changeset(socket, changeset_fun, item, fields, live_action)
  end

  defp changeset_fun(live_resource, :new = _live_action), do: live_resource.adapter_config(:create_changeset)
  defp changeset_fun(live_resource, :edit = _live_action), do: live_resource.adapter_config(:update_changeset)
end
