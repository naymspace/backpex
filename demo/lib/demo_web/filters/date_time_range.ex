defmodule DemoWeb.Filters.DateTimeRange do
  @moduledoc """
  Implementation of the `Backpex.Filters.Range` behaviour.
  """

  use Backpex.Filters.Range

  @impl Backpex.Filters.Range
  def type, do: :datetime

  @impl Backpex.Filter
  def label, do: "Created at"
end
