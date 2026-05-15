defmodule Backpex.Filters.Boolean do
  @moduledoc """
  The boolean filter renders one checkbox per given option, hence multiple options can apply at the same time.
  Instead of implementing a `query` callback, you need to define predicates for each option leveraging [`Ecto.Query.dynamic/2`](https://hexdocs.pm/ecto/Ecto.Query.html#dynamic/2).

  > #### Warning {: .warning}
  >
  > Note that only query elements will work as a predicate that also work in an [`Ecto.Query.where/3`](https://hexdocs.pm/ecto/Ecto.Query.html#where/3).

  If none is selected, the filter does not change the query. If multiple options are selected they are logically reduced via `orWhere`.

  See the following example for an implementation of a boolean filter for a published field.

      defmodule MyAppWeb.Filters.EventPublished do
        use Backpex.Filters.Boolean

        @impl Backpex.Filter
        def label, do: "Published?"

        @impl Backpex.Filters.Boolean
        def options do
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

  > #### `use Backpex.Filters.Boolean` {: .info}
  >
  > When you `use Backpex.Filters.Boolean`, the `Backpex.Filters.Boolean` module will set `@behavior Backpex.Filters.Boolean`.
  > In addition it will add a `render` and `render_form` function in order to display the corresponding filter.
  > It will also implement the `Backpex.Filter.query` function to define a boolean query.
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
      def query(query, attribute, value, assigns) do
        BooleanFilter.query(query, options(assigns), attribute, value, assigns)
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

  def query(query, _options, _attribute, [], _assigns), do: query

  def query(query, options, _attribute, value, _assigns) do
    Enum.reduce(value, nil, fn
      v, nil ->
        Map.get(predicates(options), v)

      v, p ->
        dynamic(^p or ^Map.get(predicates(options), v))
    end)
    |> maybe_query(query)
  end

  def maybe_query(nil, query), do: query
  def maybe_query(predicates, query), do: where(query, ^predicates)

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
  Transforms options list into a map of keys to predicates.

  ## Examples

      iex> import Ecto.Query
      iex> options = [
      ...>   %{label: "Published", key: "published", predicate: dynamic([x], x.published == true)},
      ...>   %{label: "Featured", key: "featured", predicate: dynamic([x], x.featured == true)}
      ...> ]
      iex> result = Backpex.Filters.Boolean.predicates(options)
      iex> is_map(result) and Map.has_key?(result, "published") and Map.has_key?(result, "featured")
      true

      iex> Backpex.Filters.Boolean.predicates([])
      %{}

  """
  def predicates(options) do
    options
    |> Map.new(fn %{predicate: p, key: k} -> {k, p} end)
  end
end
