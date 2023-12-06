defmodule DemoWeb.Filters.DateRange do
  @moduledoc """
  Implementation of the `Backpex.Filters.Range` behaviour.
  """

  use Backpex.Filters.Range

  @impl Backpex.Filters.Range
  def type, do: :date

  @impl Backpex.Filter
  def label, do: "Begins at"
end
