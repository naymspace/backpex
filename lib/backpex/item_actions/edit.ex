defmodule Backpex.ItemActions.Edit do
  @moduledoc """
  Inline item action to redirect to edit view.
  """

  use BackpexWeb, :item_action

  require Backpex

  @impl Backpex.ItemAction
  def icon(assigns, _item) do
    ~H"""
    <Backpex.HTML.CoreComponents.icon
      name="hero-pencil-square"
      class="h-5 w-5 cursor-pointer transition duration-75 hover:scale-110 hover:text-blue-600"
    />
    """
  end

  @impl Backpex.ItemAction
  def label(assigns, _item), do: Backpex.__("Edit", assigns.live_resource)

  @impl Backpex.ItemAction
  def link(assigns, item) do
    query_params =
      case Map.get(assigns, :return_to) do
        nil -> %{}
        return_to -> %{return_to: return_to}
      end

    Router.get_path(assigns.socket, assigns.live_resource, assigns.params, :edit, item, query_params)
  end

  @impl Backpex.ItemAction
  def handle(socket, [item | _items], _data) do
    query_params =
      case Map.get(socket.assigns, :return_to) do
        nil -> %{}
        return_to -> %{return_to: return_to}
      end

    path = Router.get_path(socket, socket.assigns.live_resource, socket.assigns.params, :edit, item, query_params)

    {:ok, Phoenix.LiveView.push_navigate(socket, to: path)}
  end
end
