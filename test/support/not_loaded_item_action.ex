defmodule Backpex.Test.NotLoadedItemAction do
  @moduledoc """
  An item action that tests unload to check that Backpex loads an item action before looking at its callbacks. No other
  test uses it, so unloading it doesn't affect them or the coverage of Backpex.
  """
  use BackpexWeb, :item_action

  @impl Backpex.ItemAction
  def icon(assigns, _item), do: ~H""

  @impl Backpex.ItemAction
  def label(_assigns, _item), do: "Not loaded"

  @impl Backpex.ItemAction
  def confirm(_assigns), do: "Are you sure?"

  @impl Backpex.ItemAction
  def handle(socket, _items, _data), do: {:ok, socket}
end
