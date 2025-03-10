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

  @doc """
  The list of options for the multi select filter.
  """
  @callback options :: [{String.t() | atom(), String.t() | atom()}]

  defmacro __using__(_opts) do
    quote do
      use BackpexWeb, :filter
      use Backpex.Filter

      alias Backpex.Filters.MultiSelect, as: MultiSelectFilter

      @behaviour Backpex.Filters.Select

      @impl Backpex.Filter
      defdelegate query(query, attribute, value), to: MultiSelectFilter

      @impl Backpex.Filter
      def render(assigns) do
        assigns = assign(assigns, :options, options())
        MultiSelectFilter.render(assigns)
      end

      @impl Backpex.Filter
      def render_form(assigns) do
        assigns =
          assigns
          |> assign(:options, options())
          |> assign(:prompt, prompt())

        MultiSelectFilter.render_form(assigns)
      end

      defoverridable query: 3, render: 1, render_form: 1
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

  def render_form(assigns) do
    value = if is_nil(assigns.value), do: [], else: assigns.value
    assigns = assign(assigns, :value, value)

    ~H"""
    <div class="dropdown mt-2 w-full" phx-click={open_content()} phx-click-away={close_content()}>
      <div tabindex="0" role="button" class="select select-sm">
        <%= if @value == [] do %>
          {@prompt}
        <% else %>
          {"#{Enum.count(@value)} #{Backpex.translate("selected")}"}
        <% end %>
      </div>
      <ul
        tabindex="0"
        class="dropdown-content z-[1] menu bg-base-100 rounded-box min-w-60 hidden max-h-96 w-max overflow-y-auto p-2 shadow"
      >
        <div class="space-y-2">
          <input type="hidden" name={@form[@field].name} value="" />
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
      </ul>
    </div>
    """
  end

  defp open_content(js \\ %JS{}) do
    js
    |> JS.remove_class("hidden", to: {:inner, ".dropdown-content"})
  end

  defp close_content(js \\ %JS{}) do
    js
    |> JS.add_class("hidden", to: {:inner, ".dropdown-content"})
  end

  def query(query, _attribute, []), do: query

  def query(query, attribute, value) do
    Enum.reduce(value, nil, fn
      v, nil ->
        dynamic([x], field(x, ^attribute) == ^v)

      v, p ->
        dynamic([x], ^p or field(x, ^attribute) == ^v)
    end)
    |> maybe_query(query)
  end

  def maybe_query(nil, query), do: query
  def maybe_query(predicates, query), do: where(query, ^predicates)

  def option_value_to_label(options, values) do
    Enum.map(values, fn key -> find_option_label(options, key) end)
    |> Enum.intersperse(", ")
  end

  def find_option_label(options, key) do
    Enum.find_value(options, fn {l, k} ->
      if to_string(k) == to_string(key), do: l
    end) || ""
  end
end
