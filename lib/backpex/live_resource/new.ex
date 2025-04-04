defmodule Backpex.LiveResource.New do
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
    if not live_resource.can?(socket.assigns, :new, nil), do: raise(Backpex.ForbiddenError)

    create_button_label = Backpex.__({"New %{resource}", %{resource: live_resource.singular_name()}}, live_resource)

    socket
    |> assign(:live_resource, live_resource)
    |> assign(:panels, live_resource.panels())
    |> assign(:fluid?, live_resource.config(:fluid?))
    |> assign(:create_button_label, create_button_label)
    |> assign(:page_title, create_button_label)
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
    adapter_config = socket.assigns.live_resource.config(:adapter_config)
    empty_item = adapter_config[:schema].__struct__()

    assign(socket, :item, empty_item)
  end

  defp assign_fields(socket) do
    fields =
      socket.assigns.live_resource.validated_fields()
      |> LiveResource.filtered_fields_by_action(socket.assigns, :new)

    assign(socket, :fields, fields)
  end

  defp assign_changeset(socket) do
    %{live_resource: live_resource, item: item, fields: fields} = socket.assigns
    create_changeset = live_resource.config(:adapter_config)[:create_changeset]

    LiveResource.assign_changeset(socket, create_changeset, item, fields, :edit)
  end
end
