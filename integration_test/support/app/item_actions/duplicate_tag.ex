defmodule Backpex.Test.ItemActions.DuplicateTag do
  @moduledoc """
  An item action with fields that creates a copy of a tag and opens it.
  """

  use BackpexWeb, :item_action

  alias Backpex.Test.Repo
  alias Backpex.Test.Tag

  @impl Backpex.ItemAction
  def icon(assigns, _item) do
    ~H"""
    <Backpex.HTML.CoreComponents.icon name="hero-document-duplicate" class="h-5 w-5" />
    """
  end

  @impl Backpex.ItemAction
  def fields do
    [
      name: %{module: Backpex.Fields.Text, label: "Name"}
    ]
  end

  @impl Backpex.ItemAction
  def label(_assigns, nil), do: "Duplicate"
  def label(_assigns, item), do: "Duplicate #{item.name}"

  @impl Backpex.ItemAction
  def confirm(_assigns), do: "Please complete the form to duplicate the item."

  @impl Backpex.ItemAction
  def confirm_label(_assigns), do: "Duplicate"

  @impl Backpex.ItemAction
  def changeset(item, change, metadata), do: Tag.changeset(item, change, metadata)

  @impl Backpex.ItemAction
  def base_schema(assigns) do
    [item | _other] = assigns.selected_items

    item
  end

  @impl Backpex.ItemAction
  def handle(socket, _items, data) do
    {:ok, created} =
      %Tag{}
      |> Tag.changeset(Map.from_struct(data))
      |> Repo.insert()

    %{live_resource: live_resource, params: params} = socket.assigns

    {:ok, push_navigate(socket, to: Router.get_path(socket, live_resource, params, :show, created))}
  end
end
