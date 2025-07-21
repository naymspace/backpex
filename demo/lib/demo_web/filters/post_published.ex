defmodule DemoWeb.Filters.PostPublished do
  @moduledoc """
  Implementation of the `Backpex.Filters.Boolean` behaviour.
  """

  use Backpex.Filters.Boolean

  @impl Backpex.Filter
  def label, do: "Published?"

  @impl Backpex.Filters.Boolean
  def options(_assigns) do
    [
      %{
        label: "Published",
        key: "published",
        predicate: dynamic([x], x.published)
      },
      %{
        label: "Not published",
        key: "not_published",
        predicate: dynamic([x], not x.published)
      }
    ]
  end
end
