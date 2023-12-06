defmodule DemoWeb.Filters.PostLikeRange do
  @moduledoc """
  Implementation of the `Backpex.Filters.Range` behaviour.
  """

  use Backpex.Filters.Range

  @impl Backpex.Filters.Range
  def type, do: :number

  @impl Backpex.Filter
  def label, do: "Likes"
end
