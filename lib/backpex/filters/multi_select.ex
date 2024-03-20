defmodule Backpex.Filters.MultiSelect do
  @moduledoc """
  The multi select filter behaviour. Renders a multi select box for the implemented `options/0` callback.
  `prompt/0` defines the label for the multi select box.

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
  > When you `use Backpex.Filters.MultiSelect`, the `Backpex.Filters.MultiSelect` module will set `@behavior Backpex.Filters.Select`.
  > In addition it will add a `render` and `render_form` function in order to display the corresponding filter.
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
    <%= @label %>
    """
  end

  attr :form, :any, required: true
  attr :field, :atom, required: true
  attr :value, :any, required: true
  attr :options, :list, required: true
  attr :prompt, :string, required: true

  def render_form(assigns) do
    checked = if is_nil(assigns.value), do: [], else: assigns.value
    assigns = assign(assigns, :checked, checked)

    ~H"""
    <div class="mt-2" x-data="{ open: false }">
      <div tabindex="0" @click="open = !open" role="button" class="select select-sm select-bordered w-full">
        <%= if @checked == [] do %>
          <%= @prompt %>
        <% else %>
          <%= "#{Enum.count(@checked)} #{Backpex.translate("selected")}" %>
        <% end %>
      </div>
      <ul
        tabindex="0"
        class="dropdown-content z-[1] menu bg-base-100 rounded-box min-w-60 max-h-96 w-max overflow-y-auto p-2 shadow"
        x-show="open"
        @click.outside="open = false"
      >
        <div class="space-y-2">
          <%= Phoenix.HTML.Form.hidden_input(@form, @field, name: Phoenix.HTML.Form.input_name(@form, @field), value: "") %>
          <%= for {label, key} <- @options do %>
            <label class="flex cursor-pointer items-center gap-x-2">
              <%= Phoenix.HTML.Form.checkbox(
                @form,
                @field,
                name: Phoenix.HTML.Form.input_name(@form, @field) <> "[]",
                class: "checkbox checkbox-sm checkbox-primary",
                checked: to_string(key) in @checked,
                checked_value: key,
                unchecked_value: "",
                hidden_input: false
              ) %>
              <span class="label-text">
                <%= label %>
              </span>
            </label>
          <% end %>
        </div>
      </ul>
    </div>
    """
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
      if k == key, do: l
    end) || ""
  end
end
