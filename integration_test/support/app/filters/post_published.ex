defmodule Backpex.Test.Filters.PostPublished do
  @moduledoc "A boolean filter with an option for published and one for unpublished posts."

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
