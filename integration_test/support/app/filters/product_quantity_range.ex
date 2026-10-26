defmodule Backpex.Test.Filters.ProductQuantityRange do
  @moduledoc "A number range filter on the quantity of products."

  use Backpex.Filters.Range

  @impl Backpex.Filters.Range
  def type, do: :number

  @impl Backpex.Filter
  def label, do: "Quantity"
end
