defmodule Backpex.Test.Filters.DateTimeRange do
  @moduledoc "A datetime range filter on the creation time of posts."

  use Backpex.Filters.Range

  @impl Backpex.Filters.Range
  def type, do: :datetime

  @impl Backpex.Filter
  def label, do: "Created at"
end
