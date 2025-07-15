defmodule Backpex.ItemActions.Delete do
  @moduledoc """
  Inline item action to redirect to show view.
  """

  use BackpexWeb, :item_action

  alias Backpex.Resource

  require Logger
  require Backpex

  @impl Backpex.ItemAction
  def icon(assigns, _item) do
    ~H"""
    <Backpex.HTML.CoreComponents.icon
      name="hero-trash"
      class="h-5 w-5 cursor-pointer transition duration-75 hover:scale-110 hover:text-red-600"
    />
    """
  end

  @impl Backpex.ItemAction
  def label(assigns, _item), do: Backpex.__("Delete", assigns.live_resource)

  @impl Backpex.ItemAction
  def confirm(assigns) do
    count = Enum.count(assigns.selected_items)

    if count > 1 do
      Backpex.__({"Are you sure you want to delete %{count} items?", %{count: count}}, assigns.live_resource)
    else
      Backpex.__("Are you sure you want to delete the item?", assigns.live_resource)
    end
  end

  @impl Backpex.ItemAction
  def confirm_label(assigns), do: Backpex.__("Delete", assigns.live_resource)

  @impl Backpex.ItemAction
  def cancel_label(assigns), do: Backpex.__("Cancel", assigns.live_resource)

  @impl Backpex.ItemAction
  def handle(socket, items, _data) do
    {:ok, deleted_items} = Resource.delete_all(items, socket.assigns.live_resource)

    Enum.each(deleted_items, fn deleted_item -> socket.assigns.live_resource.on_item_deleted(socket, deleted_item) end)

    socket
    |> clear_flash()
    |> put_flash(:info, success_message(socket.assigns, deleted_items))
    |> ok()
  rescue
    error ->
      Logger.error("An error occurred while deleting the resource: #{inspect(error)}")

      socket
      |> clear_flash()
      |> put_flash(:error, error_message(socket.assigns, error, items))
      |> ok()
  end

  defp success_message(assigns, [_item]) do
    Backpex.__(
      {"%{resource} has been deleted successfully.", %{resource: assigns.live_resource.singular_name()}},
      assigns.live_resource
    )
  end

  defp success_message(assigns, items) do
    Backpex.__(
      {"%{count} %{resources} have been deleted successfully.",
       %{resources: assigns.live_resource.plural_name(), count: Enum.count(items)}},
      assigns.live_resource
    )
  end

  defp error_message(
         assigns,
         %Postgrex.Error{postgres: %{code: :foreign_key_violation}},
         [_item] = items
       ) do
    "#{error_message(assigns, :error, items)} #{Backpex.__("The item is used elsewhere.", assigns.live_resource)}"
  end

  defp error_message(assigns, %Ecto.ConstraintError{type: :foreign_key}, [_item] = items) do
    "#{error_message(assigns, :error, items)} #{Backpex.__("The item is used elsewhere.", assigns.live_resource)}"
  end

  defp error_message(assigns, %Postgrex.Error{postgres: %{code: :foreign_key_violation}}, items) do
    "#{error_message(assigns, :error, items)} #{Backpex.__("The items are used elsewhere.", assigns.live_resource)}"
  end

  defp error_message(assigns, %Ecto.ConstraintError{type: :foreign_key}, items) do
    "#{error_message(assigns, :error, items)} #{Backpex.__("The items are used elsewhere.", assigns.live_resource)}"
  end

  defp error_message(assigns, _error, [_item]) do
    Backpex.__(
      {"An error occurred while deleting the %{resource}!", %{resource: assigns.live_resource.singular_name()}},
      assigns.live_resource
    )
  end

  defp error_message(assigns, _error, items) do
    Backpex.__(
      {"An error occurred while deleting %{count} %{resources}!",
       %{resources: assigns.live_resource.plural_name(), count: Enum.count(items)}},
      assigns.live_resource
    )
  end
end
