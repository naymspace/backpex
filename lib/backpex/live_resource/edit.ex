defmodule Backpex.LiveResource.Edit do
  @moduledoc false
  use BackpexWeb, :html

  import Phoenix.Component

  alias Backpex.Resource
  alias Backpex.LiveResource
  alias Backpex.ResourceAction
  alias Backpex.Adapters.Ecto, as: EctoAdapter
  alias Backpex.Router
  alias Phoenix.LiveView

  require Backpex

  def mount(params, _session, socket, live_resource) do
    socket
    |> assign(:live_resource, live_resource)
    |> assign(:panels, live_resource.panels())
    |> assign(:fluid?, live_resource.config(:fluid?))
    |> assign(:page_title, Backpex.__({"Edit %{resource}", %{resource: live_resource.singular_name()}}, live_resource))
    |> assign(:params, params)
    |> assign_fields()
    |> assign_item()
    |> assign_changeset()
    |> ok()
  end

  def handle_params(_params, _url, socket) do
    noreply(socket)
  end

  def render(assigns) do
    Backpex.HTML.Resource.resource_form(assigns)
  end

  def handle_info({:update_changeset, changeset}, socket) do
    socket
    |> assign(:changeset, changeset)
    |> noreply()
  end

  def handle_info({:put_assoc, {key, value} = _assoc}, socket) do
    changeset = Ecto.Changeset.put_assoc(socket.assigns.changeset, key, value)
    assocs = Map.get(socket.assigns, :assocs, []) |> Keyword.put(key, value)

    socket
    |> assign(:assocs, assocs)
    |> assign(:changeset, changeset)
    |> noreply()
  end

  defp assign_item(socket) do
    %{live_resource: live_resource, params: params} = socket.assigns

    backpex_id = Map.fetch!(params, "backpex_id")
    primary_value = URI.decode(backpex_id)

    item = Resource.get!(primary_value, socket.assigns, live_resource)

    if not live_resource.can?(socket.assigns, :edit, item), do: raise(Backpex.ForbiddenError)

    assign(socket, :item, item)
  end

  defp assign_fields(socket) do
    fields =
      socket.assigns.live_resource.validated_fields()
      |> LiveResource.filtered_fields_by_action(socket.assigns, :edit)

    assign(socket, :fields, fields)
  end

  defp assign_changeset(socket) do
    %{live_resource: live_resource, item: item, fields: fields} = socket.assigns
    update_changeset = live_resource.config(:adapter_config)[:update_changeset]

    LiveResource.assign_changeset(socket, update_changeset, item, fields, :edit)
  end
end
