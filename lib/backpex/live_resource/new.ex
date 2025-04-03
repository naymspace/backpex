defmodule Backpex.LiveResource.New do
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

    socket
    |> assign(:live_resource, live_resource)
    |> assign(:panels, live_resource.panels())
    |> assign(:fluid?, live_resource.config(:fluid?))
    |> assign(
      :create_button_label,
      Backpex.__({"New %{resource}", %{resource: live_resource.singular_name()}}, live_resource)
    )
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

  defp apply_action(socket, :new) do
    %{live_resource: live_resource, create_button_label: create_button_label} = socket.assigns

    if not live_resource.can?(socket.assigns, :new, nil), do: raise(Backpex.ForbiddenError)

    fields = live_resource.validated_fields() |> LiveResource.filtered_fields_by_action(socket.assigns, :new)
    adapter_config = live_resource.config(:adapter_config)
    empty_item = adapter_config[:schema].__struct__()

    socket
    |> assign(:page_title, create_button_label)
    |> assign(:fields, fields)
    |> assign(:item, empty_item)
    |> LiveResource.assign_changeset(adapter_config[:create_changeset], empty_item, fields, :new)
  end
end
