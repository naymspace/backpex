defmodule DemoWeb.Filters.PostPublished do
  @moduledoc """
  Implementation of the `Backpex.Filters.Boolean` behaviour.
  """

  use Backpex.Filters.Boolean

  alias Backpex.Filters.Boolean

  @impl Backpex.Filter
  def label, do: "Published?"

  @impl Boolean
  def options(_assigns) do
    [
      %{
        label: "Published",
        key: "published",
        predicate: {:==, :published, true}
      },
      %{
        label: "Not published",
        key: "not_published",
        predicate: {:==, :published, false}
      }
    ]
  end
end
