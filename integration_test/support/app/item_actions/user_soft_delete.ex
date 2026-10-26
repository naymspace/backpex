defmodule Backpex.Test.ItemActions.UserSoftDelete do
  @moduledoc """
  An item action with fields that soft deletes users and unassigns their posts, with the labels of the default delete
  item action.
  """

  use BackpexWeb, :item_action

  import Ecto.Changeset

  alias Backpex.ItemActions.Delete

  @impl Backpex.ItemAction
  def icon(assigns, _item) do
    ~H"""
    <Backpex.HTML.CoreComponents.icon name="hero-trash" class="h-5 w-5" />
    """
  end

  @impl Backpex.ItemAction
  def fields do
    [
      reason: %{module: Backpex.Fields.Textarea, label: "Reason", type: :string}
    ]
  end

  @impl Backpex.ItemAction
  def changeset(change, attrs, _metadata) do
    change
    |> cast(attrs, [:reason])
    |> validate_required([:reason])
  end

  @impl Backpex.ItemAction
  def label(assigns, item), do: Delete.label(assigns, item)

  @impl Backpex.ItemAction
  def confirm_label(assigns), do: Delete.confirm_label(assigns)

  @impl Backpex.ItemAction
  def confirm(_assigns), do: "Why do you want to delete the selected items?"

  @impl Backpex.ItemAction
  def handle(socket, items, _data) do
    # Backpex re-read these items and authorized exactly them under this action's key before calling handle/3, so the
    # write does not check again.
    {:ok, _count} =
      Backpex.Resource.update_all(
        items,
        [set: [deleted_at: DateTime.utc_now(:second)]],
        socket.assigns,
        socket.assigns.live_resource,
        event_name: "deleted",
        authorize?: false
      )

    # Unassigning the posts is a cascade write on another resource, not a user-initiated action on it, so it skips
    # authorization deliberately.
    for item <- items do
      Backpex.Resource.update_all(item.posts, [set: [user_id: nil]], socket.assigns, Backpex.Test.PostLive,
        event_name: "updated",
        authorize?: false
      )
    end

    {:ok, put_flash(socket, :info, success_message(socket.assigns, items))}
  end

  defp success_message(assigns, [_item]), do: "#{assigns.live_resource.singular_name()} has been deleted successfully."

  defp success_message(assigns, items),
    do: "#{length(items)} #{assigns.live_resource.plural_name()} have been deleted successfully."
end
