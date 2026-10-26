defmodule Backpex.Test.Filters.PostLikeRange do
  @moduledoc "A number range filter on the likes of posts."

  use Backpex.Filters.Range

  @impl Backpex.Filters.Range
  def type, do: :number

  @impl Backpex.Filter
  def label, do: "Likes"
end
