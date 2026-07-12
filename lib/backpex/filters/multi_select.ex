defmodule Backpex.Filters.MultiSelect do
  @moduledoc """
  The multi select filter renders checkboxes for a given list of options, hence allowing the user to select multiple values.

  See the following example for an implementation of a multi select user filter.

      defmodule MyAppWeb.Filters.MultiUserSelect do
        use Backpex.Filters.MultiSelect

        @impl Backpex.Filter
        def label, do: "User"

        @impl Backpex.Filters.MultiSelect
        def prompt, do: "Select user ..."

        @impl Backpex.Filters.MultiSelect
        def options, do: [
          {"John Doe", "acdd1860-65ce-4ed6-a37c-433851cf68d7"},
          {"Jane Doe", "9d78ce5e-9334-4a6c-a076-f1e72522de2"}
        ]
      end

  > #### `use Backpex.Filters.MultiSelect` {: .info}
  >
  > When you `use Backpex.Filters.MultiSelect`, the `Backpex.Filters.MultiSelect` module will set `@behavior Backpex.Filters.Select`. In addition it will add a `render` and `render_form` function in order to display the corresponding filter.
  """
  use BackpexWeb, :filter

  import Backpex.HTML.CoreComponents

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
      def type(_assigns), do: {:array, :string}

      @impl Backpex.Filter
      def changeset(changeset, field, assigns) do
        MultiSelectFilter.changeset(changeset, field, options(assigns))
      end

      @impl Backpex.Filter
      defdelegate query(query, attribute, value, assigns), to: MultiSelectFilter

      @impl Backpex.Filter
      def render(assigns) do
        assigns = assign(assigns, :options, options(assigns))
        MultiSelectFilter.render(assigns)
      end

      @impl Backpex.Filter
      def render_form(assigns) do
        assigns =
          assigns
          |> assign(:options, options(assigns))
          |> assign(:prompt, prompt())

        MultiSelectFilter.render_form(assigns)
      end

      defoverridable type: 1, changeset: 3, query: 4, render: 1, render_form: 1
    end
  end

  attr :value, :any, required: true
  attr :options, :list, required: true

  def render(assigns) do
    assigns = assign(assigns, :label, option_value_to_label(assigns.options, assigns.value))

    ~H"""
    {@label}
    """
  end

  attr :form, :any, required: true
  attr :field, :atom, required: true
  attr :value, :any, required: true
  attr :options, :list, required: true
  attr :prompt, :string, required: true
  attr :errors, :list, default: []

  def render_form(assigns) do
    value = if is_nil(assigns.value), do: [], else: assigns.value

    trigger_text =
      case assigns.value do
        v when is_nil(v) or v == [] -> assigns.prompt
        _prompt -> "#{Enum.count(assigns.value)} #{Backpex.__("selected", assigns.live_resource)}"
      end

    assigns =
      assigns
      |> assign(:value, value)
      |> assign(:trigger_text, trigger_text)

    ~H"""
    <.dropdown id={"multi-select-#{@form.id}"} class="mt-2 w-full">
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
  Validates that all selected values exist in the options list.

  Returns the changeset unchanged if all values are valid, or adds an error if any value is not found in options.
  """
  def changeset(changeset, field, options) do
    valid_values = Enum.map(options, fn {_label, value} -> to_string(value) end)

    Ecto.Changeset.validate_change(changeset, field, fn _field, values ->
      validate_subset(values || [], valid_values, field)
    end)
  end

  defp validate_subset(values, valid_values, field) do
    if Enum.all?(values, &(to_string(&1) in valid_values)),
      do: [],
      else: [{field, "contains invalid options"}]
  end

  def query(query, _attribute, [], _assigns), do: query

  def query(query, attribute, values, _assigns) do
    where(query, [x], field(x, ^attribute) in ^values)
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
