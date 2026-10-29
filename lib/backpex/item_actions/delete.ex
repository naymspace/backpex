defmodule Backpex.ItemActions.Delete do
  @moduledoc """
  Inline item action to delete the item.
  """

  use BackpexWeb, :item_action

  alias Backpex.Resource

  require Backpex
  require Logger

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
    case before_delete(socket, items) do
      :ok ->
        delete(socket, items)

      {:error, message} ->
        socket
        |> clear_flash()
        |> put_flash(:error, message)
        |> stay_on_show_view(items)
        |> ok()
    end
  end

  # The show view navigates to the index view after an item action unless the action navigated itself. When the
  # deletion is refused, the item still exists, so the user stays on its show view.
  defp stay_on_show_view(%{assigns: %{live_action: :show}} = socket, [item]) do
    %{live_resource: live_resource, params: params} = socket.assigns
    path = Router.get_path(socket, live_resource, params, :show, item, Map.take(params, ["return_to"]))

    push_patch(socket, to: path)
  end

  defp stay_on_show_view(socket, _items), do: socket

  # Stops at the first item that may not be deleted, as none of the items are deleted then.
  defp before_delete(socket, items) do
    %{live_resource: live_resource} = socket.assigns

    Enum.reduce_while(items, :ok, fn item, :ok ->
      case live_resource.on_item_deleting(socket, item) do
        :ok ->
          {:cont, :ok}

        {:error, message} = error when is_binary(message) ->
          {:halt, error}

        other ->
          raise ArgumentError, """
          Invalid return value from #{inspect(live_resource)}.on_item_deleting/2.

          Expected: :ok or {:error, message}, where message is a string
          Got: #{inspect(other)}
          """
      end
    end)
  end

  defp delete(socket, items) do
    %{live_resource: live_resource} = socket.assigns

    # Backpex only calls `handle/3` once `Backpex.ItemAction.authorize_fresh!/3` has re-read these
    # items and authorized exactly them under exactly this action's key — `items` *is* that re-read
    # list. Re-checking here would run the user's `can?/3` a second time for the same decision.
    {:ok, deleted_items} = Resource.delete_all(items, socket.assigns, live_resource, authorize?: false)

    Enum.each(deleted_items, fn deleted_item -> live_resource.on_item_deleted(socket, deleted_item) end)

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

  defp error_message(assigns, %Postgrex.Error{postgres: %{code: :foreign_key_violation}}, [_item] = items) do
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
