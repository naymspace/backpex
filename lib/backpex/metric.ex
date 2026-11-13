defmodule Backpex.Metric do
  @config_schema [
    module: [
      doc: "The metric module, which implements the `Backpex.Metric` behaviour.",
      type: :atom,
      required: true
    ],
    select: [
      doc: """
      The expression passed to `c:query/3`, usually a `dynamic` with an aggregate function. Required unless the
      metric module implements `c:data/2`.
      """,
      type: :any
    ]
  ]

  @moduledoc """
  Behaviour implemented by all metrics.

  Metrics are info boxes for your resources displaying key indicators prominently on the index view in your application.
  An example could be to show the current total of all orders received today. You may create your own metrics by
  implementing this behaviour.

  See the [Metrics](metrics.md) guide for how to add metrics to a LiveResource.

  ## Data of your own

  By default, Backpex passes the query of the index view, after search and filters, to `c:query/3`. A metric module
  that gets its data in another way, e.g. from a function of your context module, implements `c:data/2` instead.
  Backpex then calls it with the metric and the assigns of the index view, so the metric can read the values of the
  active filters from `:filter_values` and anything else the LiveView assigns, e.g. the current user:

      @impl Backpex.Metric
      def data(_metric, assigns), do: MyApp.Absences.vacation_balance(assigns.current_user, assigns.filter_values)

  ## Configuration

  `c:Backpex.LiveResource.metrics/0` returns a keyword list with one map per metric. Backpex validates each map when
  the index view loads and raises a configuration error that names the LiveResource and the metric. Every metric
  takes these options:

  #{NimbleOptions.docs(@config_schema)}

  The metric module receives the whole map in `c:render/1` and `c:data/2`, so it can read options of its own. A
  module that implements `c:config_schema/0` returns the NimbleOptions schema of these options, as
  `Backpex.Metrics.Value` does. Backpex then validates the map against it and rejects every key that is in neither
  schema, e.g. a typo. For a module without `c:config_schema/0`, only the options above are validated and other keys
  are passed on as they are.

      @impl Backpex.Metric
      def config_schema do
        [
          label: [type: :string, required: true],
          color: [type: {:in, [:primary, :secondary]}]
        ]
      end
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

  @doc """
  Returns the NimbleOptions schema of the options the metric module reads from its configuration map, see the
  [Configuration](#module-configuration) section.
  """
  @callback config_schema() :: keyword()

  @optional_callbacks query: 3, data: 2, config_schema: 0

  # `:select` is required when Backpex gets the data with `c:query/3`.
  @query_config_schema put_in(@config_schema, [:select, :required], true)

  # Compiled once: `NimbleOptions.validate/2` validates a keyword list schema itself on every call.
  @compiled_config_schema NimbleOptions.new!(@config_schema)
  @compiled_query_config_schema NimbleOptions.new!(@query_config_schema)

  @doc false
  def validate_configs!(metrics, live_resource) do
    Backpex.LiveResource.Config.validate_each!(metrics, "metric", "metrics/0", live_resource, &validate_config/1)
  end

  defp validate_config(options) do
    module = options[:module]
    loaded? = is_atom(module) and Code.ensure_loaded?(module)

    data? = loaded? and function_exported?(module, :data, 2)

    if loaded? and function_exported?(module, :config_schema, 0) do
      base_schema = if data?, do: @config_schema, else: @query_config_schema

      NimbleOptions.validate(options, compiled_module_schema(module, base_schema))
    else
      # The module receives the map and has no schema for its own options, so unknown keys are not rejected.
      options
      |> Keyword.take(Keyword.keys(@config_schema))
      |> NimbleOptions.validate(if(data?, do: @compiled_config_schema, else: @compiled_query_config_schema))
    end
  end

  # The schema of a metric module is only known at runtime, so the compiled schema is kept in a persistent term. It
  # is compiled again when `c:config_schema/0` returns another schema, e.g. after the module was recompiled.
  defp compiled_module_schema(module, base_schema) do
    schema = Keyword.merge(base_schema, module.config_schema())
    key = {__MODULE__, module}

    case :persistent_term.get(key, nil) do
      {^schema, compiled_schema} ->
        compiled_schema

      _other ->
        compiled_schema = NimbleOptions.new!(schema)
        :persistent_term.put(key, {schema, compiled_schema})
        compiled_schema
    end
  end

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
