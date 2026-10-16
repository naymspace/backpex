defmodule Backpex.Filters.Boolean do
  @moduledoc """
  The boolean filter renders one checkbox per given option, hence multiple options can apply at the same time.
  Instead of implementing a `condition/3` callback, you need to define a predicate for each option. A predicate is a
  condition, see `t:Backpex.Filter.condition/0`.

  If none is selected, the filter keeps all items. If multiple options are selected, it keeps the items that match any
  of their predicates.

  See the following example for an implementation of a boolean filter for a published field.

      defmodule MyAppWeb.Filters.EventPublished do
        use Backpex.Filters.Boolean

        @impl Backpex.Filter
        def label, do: "Published?"

        @impl Backpex.Filters.Boolean
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

  > #### `use Backpex.Filters.Boolean` {: .info}
  >
  > When you `use Backpex.Filters.Boolean`, the `Backpex.Filters.Boolean` module will set `@behavior Backpex.Filters.Boolean`.
  > In addition it will add a `render` and `render_form` function in order to display the corresponding filter.
  > It will also implement the `c:Backpex.Filter.condition/3` callback to combine the predicates of the selected options.
  """
  use BackpexWeb, :filter

  @doc """
  The list of options for the select filter.
  """
  @callback options(assigns :: map()) :: [map()]

  defmacro __using__(_opts) do
    quote do
      @behaviour Backpex.Filters.Boolean

      use BackpexWeb, :filter
      use Backpex.Filter

      alias Backpex.Filters.Boolean, as: BooleanFilter

      @impl Backpex.Filter
      def type(_assigns), do: {:array, :string}

      @impl Backpex.Filter
      def changeset(changeset, field, assigns) do
        BooleanFilter.changeset(changeset, field, options(assigns))
      end

      @impl Backpex.Filter
      def condition(field, value, assigns) do
        assigns
        |> options()
        |> BooleanFilter.condition(field, value, assigns)
      end

      @impl Backpex.Filter
      def render(assigns) do
        assigns = assign(assigns, :options, options(assigns))
        BooleanFilter.render(assigns)
      end

      @impl Backpex.Filter
      def render_form(assigns) do
        assigns = assign(assigns, :options, options(assigns))
        BooleanFilter.render_form(assigns)
      end

      defoverridable type: 1, changeset: 3, condition: 3, render: 1, render_form: 1
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
  attr :errors, :list, default: []

  def render_form(assigns) do
    value = if is_nil(assigns.value), do: [], else: assigns.value
    options = Enum.map(assigns.options, fn %{label: l, key: k} -> {l, k} end)

    assigns =
      assigns
      |> assign(:value, value)
      |> assign(:options, options)

    ~H"""
    <div class="mt-2 flex flex-col space-y-2">
      <input type="hidden" name={@form[@field].name} value="" tabindex="-1" aria-hidden="true" />
      <%= for {label, v} <- @options do %>
        <label class="flex cursor-pointer items-center gap-x-2">
          <input
            id={"#{@form[@field].name}[]-#{v}"}
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
      <% end %>
    </div>
    <.error :for={msg <- @errors} class="mt-1">{msg}</.error>
    """
  end

  @doc """
  Validates that all selected values exist in the options list.

  Returns the changeset unchanged if all values are valid, or adds an error if any value is not found in options.
  """
  def changeset(changeset, field, options) do
    valid_keys = Enum.map(options, fn %{key: k} -> to_string(k) end)

    Ecto.Changeset.validate_change(changeset, field, fn _field, values ->
      validate_subset(values || [], valid_keys, field)
    end)
  end

  defp validate_subset(values, valid_keys, field) do
    if Enum.all?(values, &(to_string(&1) in valid_keys)),
      do: [],
      else: [{field, "contains invalid options"}]
  end

  @doc """
  Returns the condition for the keys of the selected options: the predicate of a single option, the predicates of
  several options combined with `:or`, or `nil` if no option is selected.

  ## Examples

      iex> options = [
      ...>   %{label: "Published", key: "published", predicate: {:==, :published, true}},
      ...>   %{label: "Featured", key: "featured", predicate: {:==, :featured, true}}
      ...> ]
      iex> Backpex.Filters.Boolean.condition(options, :status, [], %{})
      nil
      iex> Backpex.Filters.Boolean.condition(options, :status, ["published"], %{})
      {:==, :published, true}
      iex> Backpex.Filters.Boolean.condition(options, :status, ["published", "featured"], %{})
      {:or, [{:==, :published, true}, {:==, :featured, true}]}

  """
  def condition(_options, _field, [], _assigns), do: nil

  def condition(options, _field, [key], _assigns), do: options |> predicates() |> Map.get(to_string(key))

  def condition(options, _field, keys, _assigns) do
    predicates = predicates(options)

    {:or, Enum.map(keys, &Map.get(predicates, to_string(&1)))}
  end

  @doc """
  Converts a list of option values to their corresponding labels.

  Returns a list with labels interspersed with commas for display.

  ## Examples

      iex> options = [
      ...>   %{label: "Published", key: "published"},
      ...>   %{label: "Featured", key: "featured"}
      ...> ]
      iex> Backpex.Filters.Boolean.option_value_to_label(options, ["published", "featured"])
      ["Published", ", ", "Featured"]

      iex> options = [%{label: "Published", key: "published"}]
      iex> Backpex.Filters.Boolean.option_value_to_label(options, ["published"])
      ["Published"]

      iex> options = [%{label: "Published", key: "published"}]
      iex> Backpex.Filters.Boolean.option_value_to_label(options, [])
      []

      iex> options = [%{label: "Published", key: "published"}]
      iex> Backpex.Filters.Boolean.option_value_to_label(options, ["unknown"])
      [""]

  """
  def option_value_to_label(options, values) do
    Enum.map(values, fn key -> find_option_label(options, key) end)
    |> Enum.intersperse(", ")
  end

  @doc """
  Finds the label for a given option key.

  Returns empty string if the key is not found.

  ## Examples

      iex> options = [
      ...>   %{label: "Published", key: "published"},
      ...>   %{label: "Not published", key: "not_published"}
      ...> ]
      iex> Backpex.Filters.Boolean.find_option_label(options, "published")
      "Published"

      iex> options = [%{label: "Published", key: "published"}]
      iex> Backpex.Filters.Boolean.find_option_label(options, "unknown")
      ""

      iex> options = [%{label: "Published", key: "published"}]
      iex> Backpex.Filters.Boolean.find_option_label(options, :published)
      "Published"

  """
  def find_option_label(options, key) do
    Enum.find_value(options, fn option ->
      if to_string(option.key) == to_string(key), do: option.label
    end) || ""
  end

  @doc """
  Transforms options list into a map of keys to predicates. The keys are strings, as the selected keys of the filter
  are, even if the options have atom keys.

  ## Examples

      iex> options = [
      ...>   %{label: "Published", key: "published", predicate: {:==, :published, true}},
      ...>   %{label: "Featured", key: "featured", predicate: {:==, :featured, true}}
      ...> ]
      iex> Backpex.Filters.Boolean.predicates(options)
      %{"featured" => {:==, :featured, true}, "published" => {:==, :published, true}}

      iex> Backpex.Filters.Boolean.predicates([])
      %{}

  """
  def predicates(options) do
    options
    |> Map.new(fn %{predicate: p, key: k} -> {to_string(k), p} end)
  end
end
