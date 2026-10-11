defmodule Backpex.Adapters.Ecto.Filter do
  @moduledoc """
  The Ecto-specific callback of filters.

  A filter describes the items it keeps with a condition, see `c:Backpex.Filter.condition/3`. A filter that needs more
  than a condition, e.g. a fragment of SQL or a join, can implement `c:query/4` instead. Only `Backpex.Adapters.Ecto`
  calls it, so such a filter only works with this adapter.

      defmodule MyAppWeb.Filters.EventStatus do
        use Backpex.Filters.Select

        @behaviour Backpex.Adapters.Ecto.Filter

        import Ecto.Query

        @impl Backpex.Filter
        def label, do: "Status"

        @impl Backpex.Filters.Select
        def prompt, do: "Select status ..."

        @impl Backpex.Filters.Select
        def options(_assigns), do: [{"Open", "open"}, {"Closed", "closed"}]

        @impl Backpex.Adapters.Ecto.Filter
        def query(query, field, value, _assigns) do
          where(query, [event], fragment("lower(?)", field(event, ^field)) == ^value)
        end
      end
  """

  @doc """
  Applies the filter to the query of the items. Takes precedence over `c:Backpex.Filter.condition/3`.

  Receives the query, the name of the filter, its validated and cast value and the assigns.
  """
  @callback query(query :: Ecto.Query.t(), field :: atom(), value :: any(), assigns :: map()) :: Ecto.Query.t()
end
