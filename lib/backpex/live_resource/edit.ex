defmodule Backpex.LiveResource.Edit do
  @moduledoc false

  alias Backpex.Resource
  alias Backpex.LiveResource
  alias Backpex.ResourceAction
  alias Backpex.Adapters.Ecto, as: EctoAdapter
  alias Backpex.Router
  alias Phoenix.LiveView
  use BackpexWeb, :html
  import Phoenix.Component
  require Backpex

  def mount(_params, _session, socket, live_resource) do
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
    Backpex.HTML.Resource.resource_form(assigns)
  end

  def handle_info({:update_changeset, changeset}, socket) do
    socket
    |> assign(:changeset, changeset)
    |> noreply()
  end

  defp apply_action(socket, :edit) do
    %{live_resource: live_resource} = socket.assigns

    fields = live_resource.validated_fields() |> LiveResource.filtered_fields_by_action(socket.assigns, :edit)
    primary_value = URI.decode(socket.assigns.params["backpex_id"])
    item = Resource.get!(primary_value, socket.assigns, live_resource)

    if not live_resource.can?(socket.assigns, :edit, item), do: raise(Backpex.ForbiddenError)

    socket
    |> assign(:fields, fields)
    |> assign(:page_title, Backpex.__({"Edit %{resource}", %{resource: live_resource.singular_name()}}, live_resource))
    |> assign(:item, item)
    |> LiveResource.assign_changeset(live_resource.config(:adapter_config)[:update_changeset], item, fields, :edit)
  end
end
