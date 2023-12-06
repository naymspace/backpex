defmodule DemoWeb.Filters.ProductQuantityRange do
  @moduledoc """
  Implementation of the `Backpex.Filters.Range` behaviour.
  """

  use Backpex.Filters.Range

  @impl Backpex.Filters.Range
  def type, do: :number

  @impl Backpex.Filter
  def label, do: "Quantity"
end
