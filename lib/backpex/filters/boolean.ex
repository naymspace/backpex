# quokka:skip-module-directive-reordering
defmodule Backpex.Filters.Boolean do
  @config_schema [
    options: [
      doc: """
      List of options or function that receives the assigns and returns the list. An option is a map with a `:label`,
      a `:key` and a `:predicate`, the condition of the items the option keeps, see `t:Backpex.Filter.condition/0`.
      """,
      type: {:or, [{:list, :map}, {:fun, 1}]},
      required: true
    ]
  ]

  @moduledoc """
  The boolean filter renders one checkbox per given option, hence multiple options can apply at the same time.
  Instead of implementing a condition, you define a predicate for each option. A predicate is a condition, see
  `t:Backpex.Filter.condition/0`.

  If none is selected, the filter keeps all items. If multiple options are selected, it keeps the items that match any
  of their predicates.

  ## Filter-specific options

  See `Backpex.Filter` for general filter options.

  #{NimbleOptions.docs(@config_schema)}

  ## Example

  See the following example for a boolean filter for a published field.

      def filters do
        [
          published: %{
            module: Backpex.Filters.Boolean,
            label: "Published?",
            options: [
              %{label: "Published", key: "published", predicate: {:==, :published, true}},
              %{label: "Not published", key: "not_published", predicate: {:==, :published, false}}
            ]
          }
        ]
      end

  ## Reusable filter modules

  To reuse a boolean filter in several LiveResources, define a module that implements the `c:options/1` callback and use
  it as the `:module` of the filter. The `:options` option of the filter takes precedence over the callback.

      defmodule MyAppWeb.Filters.EventPublished do
        use Backpex.Filters.Boolean

        @impl Backpex.Filter
        def label, do: "Published?"

        @impl Backpex.Filters.Boolean
        def options(_assigns) do
          [
            %{label: "Published", key: "published", predicate: {:==, :published, true}},
            %{label: "Not published", key: "not_published", predicate: {:==, :published, false}}
          ]
        end
      end

  > #### `use Backpex.Filters.Boolean` {: .info}
  >
  > When you `use Backpex.Filters.Boolean`, the `Backpex.Filters.Boolean` module will set `@behavior Backpex.Filters.Boolean`.
  > In addition it will delegate the callbacks of `Backpex.Filter` to `Backpex.Filters.Boolean`, so you can override
  > any of them.
  """
  use BackpexWeb, :filter
  use Backpex.Filter, config_schema: @config_schema

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
      def config_schema, do: BooleanFilter.module_config_schema(&options/1)

      @impl Backpex.Filter
      defdelegate type(filter, assigns), to: BooleanFilter

      @impl Backpex.Filter
      defdelegate changeset(changeset, filter, assigns), to: BooleanFilter

      @impl Backpex.Filter
      defdelegate condition(filter, value, assigns), to: BooleanFilter

      @impl Backpex.Filter
      defdelegate render(assigns), to: BooleanFilter

      @impl Backpex.Filter
      defdelegate render_form(assigns), to: BooleanFilter

      defoverridable config_schema: 0, type: 2, changeset: 3, condition: 3, render: 1, render_form: 1
    end
  end

  @doc false
  # The config schema of a module that uses this module: its callback is the default of the options.
  def module_config_schema(options_fun) do
    Keyword.update!(@config_schema, :options, &(&1 |> Keyword.delete(:required) |> Keyword.put(:default, options_fun)))
  end

  @impl Backpex.Filter
  def type(_filter, _assigns), do: {:array, :string}

  @doc """
  Validates that all selected values exist in the options list.

  Returns the changeset unchanged if all values are valid, or adds an error if any value is not found in options.
  """
  @impl Backpex.Filter
  def changeset(changeset, {field, _config} = filter, assigns) do
    valid_keys = filter |> options(assigns) |> Enum.map(fn %{key: k} -> to_string(k) end)

    Ecto.Changeset.validate_change(changeset, field, fn _field, values ->
      invalid_option_errors(values || [], valid_keys, field)
    end)
  end

  defp invalid_option_errors(values, valid_keys, field) do
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
      iex> filter = {:status, %{options: options}}
      iex> Backpex.Filters.Boolean.condition(filter, [], %{})
      nil
      iex> Backpex.Filters.Boolean.condition(filter, ["published"], %{})
      {:==, :published, true}
      iex> Backpex.Filters.Boolean.condition(filter, ["published", "featured"], %{})
      {:or, [{:==, :published, true}, {:==, :featured, true}]}

  """
  @impl Backpex.Filter
  def condition(_filter, [], _assigns), do: nil

  def condition(filter, keys, assigns) do
    predicates = filter |> options(assigns) |> predicates()

    case Enum.map(keys, &Map.get(predicates, to_string(&1))) do
      [predicate] -> predicate
      predicates -> {:or, predicates}
    end
  end

  attr :filter, :any, required: true, doc: "the filter"
  attr :value, :any, required: true, doc: "the keys of the selected options"

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
  attr :value, :any, required: true, doc: "the keys of the selected options"
  attr :errors, :list, default: [], doc: "the errors of the value"

  @impl Backpex.Filter
  def render_form(assigns) do
    value = if is_nil(assigns.value), do: [], else: assigns.value
    options = assigns.filter |> options(assigns) |> Enum.map(fn %{label: l, key: k} -> {l, k} end)

    assigns =
      assigns
      |> assign(:value, value)
      |> assign(:options, options)
      |> assign_new(:errors, fn -> [] end)

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
  Returns the options of a boolean filter: its `:options` option, or the result of it if it is a function.
  """
  def options({_name, config}, assigns) do
    case Map.fetch!(config, :options) do
      options when is_function(options, 1) -> options.(assigns)
      options -> options
    end
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
