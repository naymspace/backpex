defmodule Backpex.Metric do
  @moduledoc ~S"""
  Behaviour implemented by all metrics.

  Metrics are info boxes for your resources displaying key indicators prominently on the index view in your application.
  An example could be to show the current total of all orders received today. You may create your own metrics by
  implementing this behaviour.

  ## Data of your own

  By default, Backpex passes the query of the index view, after search and filters, to `c:query/3`. A metric module
  that gets its data in another way, e.g. from a function of your context module, implements `c:data/2` instead.
  Backpex then calls it with the metric and the assigns of the index view, so the metric can read the values of the
  active filters from `:filter_values` and anything else the LiveView assigns, e.g. the current user:

      @impl Backpex.Metric
      def data(_metric, assigns), do: MyApp.Absences.vacation_balance(assigns.current_user, assigns.filter_values)
  """

  alias Phoenix.LiveView.Rendered

  @doc """
  Used to render the metric as a heex template on the index views.
  """
  @callback render(assigns :: map()) :: %Rendered{}

  @doc """
  Returns the data of the metric from the query of the index view. Not called if the metric implements `c:data/2`.
  """
  @callback query(query :: Ecto.Queryable.t(), select :: any(), repo :: Ecto.Repo.t()) ::
              Ecto.Schema.t() | term() | nil

  @doc """
  Returns the data of the metric in another way than from the query of the index view, see the
  [Data of your own](#module-data-of-your-own) section.

  Receives the metric and the assigns of the index view, which hold the validated values of the active filters under
  `:filter_values`.
  """
  @callback data(metric :: map(), assigns :: map()) :: term()

  @callback format(data :: any(), format :: any()) :: term()

  @optional_callbacks query: 3, data: 2

  @doc """
  Determine if metrics are visible for given live_resource.
  """
  def metrics_visible?(%{} = visibility, resource) when is_atom(resource) do
    metrics_visible?(visibility, Atom.to_string(resource))
  end

  def metrics_visible?(%{} = visibility, resource) do
    Map.get(visibility, resource, true)
  end
end
