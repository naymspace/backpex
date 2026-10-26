# quokka:skip-module-directive-reordering
defmodule Backpex.Filters.Select do
  @config_schema [
    options: [
      doc: "List of options as `{label, value}` tuples or function that receives the assigns and returns the list.",
      type: {:or, [{:list, :any}, {:fun, 1}]},
      required: true
    ],
    prompt: [
      doc: """
      The label of the empty option that selects no value or function that receives the assigns. Defaults to
      `"Select an option..."`.
      """,
      type: {:or, [:string, {:fun, 1}]}
    ]
  ]

  @moduledoc """
  The select filter renders a select box with the given options. It keeps the items whose field equals the selected
  value.

  ## Filter-specific options

  See `Backpex.Filter` for general filter options.

  #{NimbleOptions.docs(@config_schema)}

  ## Example

      def filters do
        [
          status: %{
            module: Backpex.Filters.Select,
            label: "Event status",
            prompt: "Select an option...",
            options: [{"Open", :open}, {"Close", :close}]
          }
        ]
      end

  ## Reusable filter modules

  To reuse a select filter in several LiveResources, define a module that implements the `c:options/1` and `c:prompt/0`
  callbacks and use it as the `:module` of the filter. The `:options` and `:prompt` options of the filter take
  precedence over the callbacks.

      defmodule MyAppWeb.Filters.EventStatusSelect do
        use Backpex.Filters.Select

        @impl Backpex.Filter
        def label, do: "Event status"

        @impl Backpex.Filters.Select
        def prompt, do: "Select an option..."

        @impl Backpex.Filters.Select
        def options(_assigns), do: [
          {"Open", :open},
          {"Close", :close},
        ]
      end

  > #### `use Backpex.Filters.Select` {: .info}
  >
  > When you `use Backpex.Filters.Select`, the `Backpex.Filters.Select` module will set `@behavior Backpex.Filters.Select`.
  > In addition it will delegate the callbacks of `Backpex.Filter` to `Backpex.Filters.Select`, so you can override any
  > of them.
  """
  use BackpexWeb, :filter
  use Backpex.Filter, config_schema: @config_schema

  require Backpex

  @doc """
  The select's default option.
  """
  @callback prompt :: String.t() | atom()

  @doc """
  The list of options for the select filter.
  """
  @callback options(assigns :: map()) :: [{String.t() | atom(), String.t() | atom()}]

  defmacro __using__(_opts) do
    quote do
      @behaviour Backpex.Filters.Select

      use BackpexWeb, :filter
      use Backpex.Filter

      alias Backpex.Filters.Select, as: SelectFilter

      @impl Backpex.Filter
      def config_schema, do: SelectFilter.module_config_schema(&options/1, &prompt/0)

      @impl Backpex.Filter
      defdelegate type(filter, assigns), to: SelectFilter

      @impl Backpex.Filter
      defdelegate changeset(changeset, filter, assigns), to: SelectFilter

      @impl Backpex.Filter
      defdelegate condition(filter, value, assigns), to: SelectFilter

      @impl Backpex.Filter
      defdelegate render(assigns), to: SelectFilter

      @impl Backpex.Filter
      defdelegate render_form(assigns), to: SelectFilter

      defoverridable config_schema: 0, type: 2, changeset: 3, condition: 3, render: 1, render_form: 1
    end
  end

  @doc false
  # The config schema of a module that uses this module: its callbacks are the defaults of the options.
  def module_config_schema(options_fun, prompt_fun) do
    @config_schema
    |> Keyword.update!(:options, &(&1 |> Keyword.delete(:required) |> Keyword.put(:default, options_fun)))
    |> Keyword.update!(:prompt, &Keyword.put(&1, :default, fn _assigns -> prompt_fun.() end))
  end

  @impl Backpex.Filter
  def type(_filter, _assigns), do: :string

  @doc """
  Validates that the selected value exists in the options list.

  Returns the changeset unchanged if the value is valid, or adds an error if not found in options.
  Empty string is allowed as it represents the "no selection" state.
  """
  @impl Backpex.Filter
  def changeset(changeset, {field, _config} = filter, assigns) do
    valid_values = ["" | filter |> options(assigns) |> Enum.map(fn {_label, value} -> to_string(value) end)]

    Ecto.Changeset.validate_inclusion(changeset, field, valid_values, message: "is not a valid option")
  end

  @doc """
  Returns the condition that keeps the items whose field equals the selected value.

  ## Examples

      iex> Backpex.Filters.Select.condition({:status, %{}}, "open", %{})
      {:==, :status, "open"}

  """
  @impl Backpex.Filter
  def condition({field, _config}, value, _assigns), do: {:==, field, value}

  attr :filter, :any, required: true, doc: "the filter"
  attr :value, :any, required: true, doc: "the selected value"

  @impl Backpex.Filter
  def render(assigns) do
    assigns = assign(assigns, :label, option_value_to_label(options(assigns.filter, assigns), assigns.value))

    ~H"""
    {@label}
    """
  end

  attr :filter, :any, required: true, doc: "the filter"
  attr :form, :any, required: true, doc: "the filter form"
  attr :field, :atom, required: true, doc: "the name of the filter"
  attr :value, :any, required: true, doc: "the selected value"
  attr :live_resource, :atom, required: true, doc: "the LiveResource"
  attr :errors, :list, default: [], doc: "the errors of the value"

  @impl Backpex.Filter
  def render_form(assigns) do
    assigns =
      assigns
      |> assign(:options, options(assigns.filter, assigns))
      |> assign(:prompt, prompt(assigns.filter, assigns))
      |> assign_new(:errors, fn -> [] end)

    ~H"""
    <select
      id={@form[@field].id}
      name={@form[@field].name}
      class={[
        "select select-sm",
        @errors != [] && "select-error bg-error/10"
      ]}
      aria-label={@prompt}
    >
      <button>
        <selectedcontent></selectedcontent>
      </button>
      <option value="">{@prompt}</option>
      {Phoenix.HTML.Form.options_for_select(@options, selected(@value))}
    </select>
    <.error :for={msg <- @errors} class="mt-1">{msg}</.error>
    """
  end

  @doc """
  Returns the options of a select filter: its `:options` option, or the result of it if it is a function.

  ## Examples

      iex> Backpex.Filters.Select.options({:status, %{options: [{"Open", :open}]}}, %{})
      [{"Open", :open}]

      iex> Backpex.Filters.Select.options({:status, %{options: fn assigns -> assigns.options end}}, %{options: []})
      []

  """
  def options({_name, config}, assigns) do
    case Map.fetch!(config, :options) do
      options when is_function(options, 1) -> options.(assigns)
      options -> options
    end
  end

  @doc """
  Returns the prompt of a select filter: its `:prompt` option, the result of it if it is a function, or
  `"Select an option..."`.
  """
  def prompt({_name, config}, assigns) do
    case Map.get(config, :prompt) do
      nil -> Backpex.__("Select an option...", assigns[:live_resource])
      prompt when is_function(prompt, 1) -> prompt.(assigns)
      prompt -> prompt
    end
  end

  @doc """
  Converts empty string to nil, returns other values as-is.

  ## Examples

      iex> Backpex.Filters.Select.selected("")
      nil

      iex> Backpex.Filters.Select.selected("open")
      "open"

      iex> Backpex.Filters.Select.selected(:open)
      :open

      iex> Backpex.Filters.Select.selected(1)
      1

  """
  def selected(""), do: nil
  def selected(value), do: value

  @doc """
  Finds the label for a given option value.

  Returns nil if the value is not found.

  ## Examples

      iex> options = [{"Open", :open}, {"Closed", :closed}]
      iex> Backpex.Filters.Select.option_value_to_label(options, "open")
      "Open"

      iex> options = [{"Open", :open}]
      iex> Backpex.Filters.Select.option_value_to_label(options, :open)
      "Open"

      iex> options = [{"Open", :open}]
      iex> Backpex.Filters.Select.option_value_to_label(options, "unknown")
      nil

      iex> options = [{"Active", "active"}, {"Inactive", "inactive"}]
      iex> Backpex.Filters.Select.option_value_to_label(options, "active")
      "Active"

      iex> options = [{"Active", "active"}]
      iex> Backpex.Filters.Select.option_value_to_label(options, :active)
      "Active"

      iex> Backpex.Filters.Select.option_value_to_label([], "value")
      nil

  """
  def option_value_to_label(options, value) do
    Enum.find_value(options, fn {option_label, option_value} ->
      if to_string(option_value) == to_string(value), do: option_label
    end)
  end
end
