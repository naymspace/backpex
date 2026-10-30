# quokka:skip-module-directive-reordering
defmodule Backpex.Filters.MultiSelect do
  @config_schema [
    options: [
      doc: "List of options as `{label, value}` tuples or function that receives the assigns and returns the list.",
      type: {:or, [{:list, :any}, {:fun, 1}]},
      required: true
    ],
    prompt: [
      doc: """
      The text of the dropdown button while no option is selected or function that receives the assigns. Defaults to
      `"Select options..."`.
      """,
      type: {:or, [:string, {:fun, 1}]}
    ]
  ]

  @moduledoc """
  The multi select filter renders checkboxes for a given list of options, hence allowing the user to select multiple
  values. It keeps the items whose field has one of the selected values.

  ## Filter-specific options

  See `Backpex.Filter` for general filter options.

  #{NimbleOptions.docs(@config_schema)}

  ## Example

      def filters do
        [
          user_id: %{
            module: Backpex.Filters.MultiSelect,
            label: "User",
            prompt: "Select user ...",
            options: fn _assigns -> MyApp.Accounts.list_user_options() end
          }
        ]
      end

  ## Reusable filter modules

  To reuse a multi select filter in several LiveResources, define a module that implements the
  `c:Backpex.Filters.Select.options/1` and `c:Backpex.Filters.Select.prompt/0` callbacks and use it as the `:module` of
  the filter. The `:options` and `:prompt` options of the filter take precedence over the callbacks.

      defmodule MyAppWeb.Filters.MultiUserSelect do
        use Backpex.Filters.MultiSelect

        @impl Backpex.Filter
        def label, do: "User"

        @impl Backpex.Filters.Select
        def prompt, do: "Select user ..."

        @impl Backpex.Filters.Select
        def options(_assigns), do: [
          {"John Doe", "acdd1860-65ce-4ed6-a37c-433851cf68d7"},
          {"Jane Doe", "9d78ce5e-9334-4a6c-a076-f1e72522de2"}
        ]
      end

  > #### `use Backpex.Filters.MultiSelect` {: .info}
  >
  > When you `use Backpex.Filters.MultiSelect`, the `Backpex.Filters.MultiSelect` module will set
  > `@behavior Backpex.Filters.Select`. In addition it will delegate the callbacks of `Backpex.Filter` to
  > `Backpex.Filters.MultiSelect`, so you can override any of them.
  """
  use BackpexWeb, :filter
  use Backpex.Filter, config_schema: @config_schema

  import Backpex.HTML.CoreComponents

  alias Backpex.Filters.Select

  require Backpex

  @doc """
  The list of options for the multi select filter.
  """
  @callback options(assigns :: map()) :: [{String.t() | atom(), String.t() | atom()}]

  defmacro __using__(_opts) do
    quote do
      @behaviour Backpex.Filters.Select

      use BackpexWeb, :filter
      use Backpex.Filter

      alias Backpex.Filters.MultiSelect, as: MultiSelectFilter

      @impl Backpex.Filter
      def config_schema, do: MultiSelectFilter.module_config_schema(&options/1, &prompt/0)

      @impl Backpex.Filter
      defdelegate type(filter, assigns), to: MultiSelectFilter

      @impl Backpex.Filter
      defdelegate changeset(changeset, filter, assigns), to: MultiSelectFilter

      @impl Backpex.Filter
      defdelegate condition(filter, value, assigns), to: MultiSelectFilter

      @impl Backpex.Filter
      defdelegate render(assigns), to: MultiSelectFilter

      @impl Backpex.Filter
      defdelegate render_form(assigns), to: MultiSelectFilter

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
  def type(_filter, _assigns), do: {:array, :string}

  @doc """
  Validates that all selected values exist in the options list.

  Returns the changeset unchanged if all values are valid, or adds an error if any value is not found in options.
  """
  @impl Backpex.Filter
  def changeset(changeset, {field, _config} = filter, assigns) do
    valid_values = filter |> Select.options(assigns) |> Enum.map(fn {_label, value} -> to_string(value) end)

    Ecto.Changeset.validate_change(changeset, field, fn _field, values ->
      invalid_option_errors(values || [], valid_values, field)
    end)
  end

  defp invalid_option_errors(values, valid_values, field) do
    if Enum.all?(values, &(to_string(&1) in valid_values)),
      do: [],
      else: [{field, "contains invalid options"}]
  end

  @doc """
  Returns the expression that keeps the items whose field has one of the selected values, or `nil` if no value is
  selected.

  ## Examples

      iex> import Backpex.Expr
      iex> Backpex.Filters.MultiSelect.condition({:status, %{}}, ["open", "pending"], %{}) ==
      ...>   expr(status in ["open", "pending"])
      true
      iex> Backpex.Filters.MultiSelect.condition({:status, %{}}, [], %{})
      nil

  """
  @impl Backpex.Filter
  def condition(_filter, [], _assigns), do: nil
  def condition({field, _config}, values, _assigns), do: expr(ref(^field) in ^values)

  attr :filter, :any, required: true, doc: "the filter"
  attr :value, :any, required: true, doc: "the selected values"

  @impl Backpex.Filter
  def render(assigns) do
    assigns = assign(assigns, :label, option_value_to_label(Select.options(assigns.filter, assigns), assigns.value))

    ~H"""
    {@label}
    """
  end

  attr :filter, :any, required: true, doc: "the filter"
  attr :form, :any, required: true, doc: "the filter form"
  attr :field, :atom, required: true, doc: "the name of the filter"
  attr :value, :any, required: true, doc: "the selected values"
  attr :live_resource, :atom, required: true, doc: "the LiveResource"
  attr :errors, :list, default: [], doc: "the errors of the values"

  @impl Backpex.Filter
  def render_form(assigns) do
    value = if is_nil(assigns.value), do: [], else: assigns.value

    trigger_text =
      case value do
        [] -> prompt(assigns.filter, assigns)
        _value -> "#{Enum.count(value)} #{Backpex.__("selected", assigns.live_resource)}"
      end

    assigns =
      assigns
      |> assign(:value, value)
      |> assign(:options, Select.options(assigns.filter, assigns))
      |> assign(:trigger_text, trigger_text)
      |> assign_new(:errors, fn -> [] end)

    ~H"""
    <.dropdown id={"multi-select-#{@form[@field].id}"} class="mt-2 w-full">
      <:trigger
        aria_label={@trigger_text}
        class={[
          "select select-sm",
          @errors != [] && "select-error bg-error/10"
        ]}
      >
        {@trigger_text}
      </:trigger>
      <:menu class="min-w-60 w-max max-h-96 overflow-y-auto">
        <div class="space-y-2 p-2">
          <input type="hidden" name={@form[@field].name} value="" tabindex="-1" aria-hidden="true" />
          <label :for={{label, v} <- @options} class="flex cursor-pointer items-center gap-x-2">
            <input
              type="checkbox"
              name={@form[@field].name <> "[]"}
              class="checkbox checkbox-sm checkbox-primary"
              value={v}
              checked={to_string(v) in @value}
            />
            <span class="label-text">
              {label}
            </span>
          </label>
        </div>
      </:menu>
    </.dropdown>
    <.error :for={msg <- @errors} class="mt-1">{msg}</.error>
    """
  end

  @doc """
  Returns the prompt of a multi select filter: its `:prompt` option, the result of it if it is a function, or
  `"Select options..."`.
  """
  def prompt({_name, config}, assigns) do
    case Map.get(config, :prompt) do
      nil -> Backpex.__("Select options...", assigns[:live_resource])
      prompt when is_function(prompt, 1) -> prompt.(assigns)
      prompt -> prompt
    end
  end

  @doc """
  Converts a list of option values to their corresponding labels.

  Returns a list with labels interspersed with commas for display.

  ## Examples

      iex> options = [{"John Doe", "uuid-1"}, {"Jane Doe", "uuid-2"}]
      iex> Backpex.Filters.MultiSelect.option_value_to_label(options, ["uuid-1", "uuid-2"])
      ["John Doe", ", ", "Jane Doe"]

      iex> options = [{"John Doe", "uuid-1"}]
      iex> Backpex.Filters.MultiSelect.option_value_to_label(options, ["uuid-1"])
      ["John Doe"]

      iex> options = [{"John Doe", "uuid-1"}]
      iex> Backpex.Filters.MultiSelect.option_value_to_label(options, [])
      []

      iex> options = [{"John Doe", "uuid-1"}]
      iex> Backpex.Filters.MultiSelect.option_value_to_label(options, ["unknown-uuid"])
      [""]

      iex> options = [{"John Doe", "uuid-1"}, {"Jane Doe", "uuid-2"}, {"Bob Smith", "uuid-3"}]
      iex> Backpex.Filters.MultiSelect.option_value_to_label(options, ["uuid-1", "uuid-2", "uuid-3"])
      ["John Doe", ", ", "Jane Doe", ", ", "Bob Smith"]

  """
  def option_value_to_label(options, values) do
    Enum.map(values, fn key -> find_option_label(options, key) end)
    |> Enum.intersperse(", ")
  end

  @doc """
  Finds the label for a given option key.

  Returns empty string if the key is not found.

  ## Examples

      iex> options = [{"John Doe", "uuid-1"}, {"Jane Doe", "uuid-2"}]
      iex> Backpex.Filters.MultiSelect.find_option_label(options, "uuid-1")
      "John Doe"

      iex> options = [{"John Doe", "uuid-1"}]
      iex> Backpex.Filters.MultiSelect.find_option_label(options, "unknown")
      ""

      iex> options = [{"Active", :active}, {"Inactive", :inactive}]
      iex> Backpex.Filters.MultiSelect.find_option_label(options, :active)
      "Active"

      iex> options = [{"Active", :active}]
      iex> Backpex.Filters.MultiSelect.find_option_label(options, "active")
      "Active"

      iex> Backpex.Filters.MultiSelect.find_option_label([{"Test", "value"}], nil)
      ""

  """
  def find_option_label(options, key) do
    Enum.find_value(options, fn {l, k} ->
      if to_string(k) == to_string(key), do: l
    end) || ""
  end
end
