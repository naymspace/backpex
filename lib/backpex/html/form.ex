defmodule Backpex.HTML.Form do
  @moduledoc """
  Contains all Backpex form components.
  """
  use BackpexWeb, :html

  import Backpex.HTML.CoreComponents

  alias Phoenix.HTML.Form

  require Backpex

  @doc """
  Renders an input.
  """
  @doc type: :component

  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :help_text, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file hidden month number password
               range radio search select tel text textarea time toggle url week)

  attr :field, Phoenix.HTML.FormField, doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"

  attr :rest, :global, include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  attr :class, :any, default: nil, doc: "additional classes for the container element"
  attr :input_class, :any, default: nil, doc: "the input class to use over defaults"
  attr :error_class, :any, default: nil, doc: "the input error class to use over defaults"

  attr :translate_error_fun, :any, default: &Function.identity/1, doc: "a custom function to map form errors"
  attr :hide_errors, :boolean, default: false, doc: "if errors should be hidden"

  slot :inner_block

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, translate_form_errors(errors, assigns.translate_error_fun))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns = assign_new(assigns, :checked, fn -> Form.normalize_value("checkbox", assigns.value) end)

    ~H"""
    <div class={["fieldset py-0", @class]}>
      <label class="label cursor-pointer">
        <input type="hidden" name={@name} value="false" />
        <input
          type="checkbox"
          id={@id}
          name={@name}
          value="true"
          checked={@checked}
          class={[@input_class || "checkbox checkbox-primary", @errors != [] && (@error_class || "!checkbox-error")]}
          {@rest}
        />{@label}
      </label>
      <.error :for={msg <- @errors} :if={not @hide_errors}>{msg}</.error>
      <.help_text :if={@help_text}>{@help_text}</.help_text>
    </div>
    """
  end

  def input(%{type: "toggle"} = assigns) do
    assigns = assign_new(assigns, :checked, fn -> Form.normalize_value("checkbox", assigns.value) end)

    ~H"""
    <div class={["fieldset py-0", @class]}>
      <label class="label cursor-pointer">
        <input type="hidden" name={@name} value="false" />
        <input
          type="checkbox"
          id={@id}
          name={@name}
          value="true"
          checked={@checked}
          class={[@input_class || "toggle toggle-primary", @errors != [] && (@error_class || "!toggle-error")]}
          {@rest}
        />{@label}
      </label>
      <.error :for={msg <- @errors} :if={not @hide_errors}>{msg}</.error>
      <.help_text :if={@help_text}>{@help_text}</.help_text>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div class={["fieldset py-0", @class]}>
      <label>
        <span :if={@label} class="label mb-1">{@label}</span>
        <select
          id={@id}
          name={@name}
          class={[
            @input_class || "select w-full",
            @errors != [] && (@error_class || "select-error text-error-content bg-error/10")
          ]}
          multiple={@multiple}
          {@rest}
        >
          <option :if={@prompt} value="">{@prompt}</option>
          {Phoenix.HTML.Form.options_for_select(@options, @value)}
        </select>
      </label>
      <.error :for={msg <- @errors} :if={not @hide_errors}>{msg}</.error>
      <.help_text :if={@help_text}>{@help_text}</.help_text>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div class={["fieldset py-0", @class]}>
      <label>
        <span :if={@label} class="label mb-1">{@label}</span>
        <textarea
          id={@id}
          name={@name}
          class={[@input_class || "textarea w-full", @errors != [] && (@error_class || "textarea-error bg-error/10")]}
          {@rest}
        >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      </label>
      <.error :for={msg <- @errors} :if={not @hide_errors}>{msg}</.error>
      <.help_text :if={@help_text}>{@help_text}</.help_text>
    </div>
    """
  end

  def input(assigns) do
    ~H"""
    <div class={["fieldset py-0", @class]}>
      <label>
        <span :if={@label} class="label mb-1">{@label}</span>
        <input
          type={@type}
          name={@name}
          id={@id}
          value={Phoenix.HTML.Form.normalize_value(@type, @value)}
          class={[@input_class || "input w-full", @errors != [] && (@error_class || "input-error bg-error/10")]}
          {@rest}
        />
      </label>
      <.error :for={msg <- @errors} :if={not @hide_errors}>{msg}</.error>
      <.help_text :if={@help_text}>{@help_text}</.help_text>
    </div>
    """
  end

  @doc """
  Renders a masked input for currencies.

  A `Phoenix.HTML.FormField` may be passed as argument, which is used to retrieve the input name, id, and values.
  Otherwise all attributes may be passed explicitly.

  ## Examples

    <.currency_input field={@form[:amount]} unit="€" unit_position={:after} />
    <.currency_input id="amount-input" name="amount" value="20" unit="$" unit_position={:before} readonly />
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :help_text, :string, default: nil
  attr :value, :any

  attr :field, Phoenix.HTML.FormField, doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []

  attr :class, :any, default: nil, doc: "additional classes for the container element"

  attr :input_class, :any,
    default: nil,
    doc: "the input class to use over defaults, note that this is applied to a wrapper span element
          to allow for proper styling of the masked input"

  attr :error_class, :any, default: nil, doc: "the input error class to use over defaults"

  attr :translate_error_fun, :any, default: &Function.identity/1, doc: "a custom function to map form errors"
  attr :hide_errors, :boolean, default: false, doc: "if errors should be hidden"

  attr :unit, :string, required: true
  attr :unit_position, :atom, required: true, values: ~w(before after)a
  attr :symbol_space, :atom, default: false
  attr :radix, :string, default: "."
  attr :thousands_separator, :string, default: ","

  attr :rest, :global, include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
              multiple pattern placeholder readonly required rows size step)

  def currency_input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, translate_form_errors(errors, assigns.translate_error_fun))
    |> assign_new(:name, fn -> field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> currency_input()
  end

  def currency_input(assigns) do
    assigns =
      assign(assigns, :mask_pattern, build_mask_pattern(assigns.unit_position, assigns.symbol_space, assigns.unit))

    ~H"""
    <div class={["fieldset py-0", @class]}>
      <span :if={@label} class="label mb-1">{@label}</span>
      <div
        id={"#{@id}-wrapper"}
        phx-hook="BackpexCurrencyInput"
        data-radix={@radix}
        data-thousands-separator={@thousands_separator}
        data-unit={@unit}
        data-mask-pattern={@mask_pattern}
      >
        <%!-- As the input ignores updates, we need to wrap it in a span to apply the styles correctly --%>
        <span class={[
          @input_class || "[&_>_input]:input [&_>_input]:w-full",
          @errors != [] && (@error_class || "[&_>_input]:input-error [&_>_input]:bg-error/10")
        ]}>
          <input id={@id} name={@name} data-masked-input phx-update="ignore" {@rest} />
          <input type="hidden" value={@value} name={@name} data-hidden-input />
        </span>
      </div>
      <.error :for={msg <- @errors} :if={not @hide_errors}>{msg}</.error>
      <.help_text :if={@help_text}>{@help_text}</.help_text>
    </div>
    """
  end

  defp build_mask_pattern(:before, true, unit), do: "#{unit} num"
  defp build_mask_pattern(:before, false, unit), do: "#{unit}num"
  defp build_mask_pattern(:after, true, unit), do: "num #{unit}"
  defp build_mask_pattern(:after, false, unit), do: "num#{unit}"

  @doc """
  Generates a generic error message.
  """
  @doc type: :component

  attr :class, :string, default: nil

  slot :inner_block, required: true

  def error(assigns) do
    ~H"""
    <p class={["text-error text-xs italic", @class]}>
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  Displays a help text.
  """
  @doc type: :component

  attr :class, :string, default: nil

  slot :inner_block, required: true

  def help_text(assigns) do
    ~H"""
    <p class={["text-base-content/60", @class]}>
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  Renders a searchable multi select.
  """
  @doc type: :component

  attr :prompt, :string, required: true, doc: "string that will be shown when no option is selected"
  attr :help_text, :string, default: nil, doc: "help text to be displayed below input"
  attr :not_found_text, :string, required: true, doc: "string that will be shown when there are no options"
  attr :options, :list, required: true, doc: "a list of options for the select"
  attr :search_input, :string, required: true, doc: "to prefill and or persist the search term for rerendering"
  attr :event_target, :any, required: true, doc: "the target that handles the events of this component"
  attr :field_options, :map, required: true, doc: "field options for the corresponding field"
  attr :field, :any, required: true, doc: "form field the select should be for"
  attr :selected, :list, required: true, doc: "the selected values"
  attr :show_select_all, :boolean, required: true, doc: "whether to display the select all button"
  attr :show_more, :boolean, required: true, doc: "whether there are more options to show"
  attr :search_event, :string, default: "search", doc: "the event that will be sent when the search input changes"
  attr :hide_search, :boolean, default: false, doc: "if search should be hidden"
  attr :hide_errors, :boolean, default: false, doc: "if errors should be hidden"
  attr :live_resource, :atom, default: nil, doc: "the live resource module"

  def multi_select(assigns) do
    errors = if Phoenix.Component.used_input?(assigns.field), do: assigns.field.errors, else: []
    translate_error_fun = Map.get(assigns.field_options, :translate_error, &Function.identity/1)
    assigns = assign(assigns, :errors, translate_form_errors(errors, translate_error_fun))

    ~H"""
    <div>
      <.dropdown id={"multi-select-#{@field.id}"} class="w-full">
        <:trigger class={[
          "input block h-fit w-full p-2",
          @errors == [] && "bg-transparent",
          @errors != [] && "input-error bg-error/10"
        ]}>
          <div class="flex h-full w-full flex-wrap items-center gap-1 px-2">
            <p :if={@selected == []} class="p-0.5 text-sm">{@prompt}</p>
            <.multi_select_badge
              :for={{label, value} <- @selected}
              live_resource={@live_resource}
              label={label}
              value={value}
              event_target={@event_target}
            />
          </div>
        </:trigger>
        <:menu class="w-full overflow-y-auto">
          <div class="max-h-72 p-2">
            <%!-- Search Input --%>
            <input
              :if={not @hide_search}
              type="search"
              name={@field.name <> "_search"}
              class="input input-sm mb-2 w-full"
              placeholder={Backpex.__("Search", @live_resource)}
              value={@search_input}
              phx-change={@search_event}
              phx-target={@event_target}
            />

            <%!-- Empty State --%>
            <p :if={@options == []} class="mt-2 w-full">{@not_found_text}</p>

            <%!-- Toggle all button --%>
            <.multi_select_toggle_all
              :if={Enum.any?(@options)}
              show_select_all={@show_select_all}
              live_resource={@live_resource}
              field={@field}
              event_target={@event_target}
            />

            <%!-- Hidden input to make sure the change is always present, even if no options are selected --%>
            <input type="hidden" name={@field.name} value="" />

            <%!-- Options --%>
            <div class="mt-2 w-full">
              <.multi_select_option
                :for={{label, value} <- @options}
                class="mt-2"
                label={label}
                value={value}
                field={@field}
                selected={@selected}
                event_target={@event_target}
              />
            </div>

            <.multi_select_show_more :if={@show_more} live_resource={@live_resource} event_target={@event_target} />
          </div>
        </:menu>
      </.dropdown>

      <.error :for={msg <- @errors} :if={not @hide_errors} class="mt-1">{msg}</.error>
      <.help_text :if={@help_text} class="mt-1">{@help_text}</.help_text>
    </div>
    """
  end

  attr :live_resource, :atom, required: true
  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :event_target, :any, required: true

  defp multi_select_badge(assigns) do
    ~H"""
    <div class="badge badge-sm badge-soft badge-primary pointer-events-auto pr-0">
      {@label}
      <div
        class="flex cursor-pointer items-center pr-2"
        role="button"
        phx-click="toggle-option"
        phx-value-id={@value}
        phx-target={@event_target}
        aria-label={Backpex.__({"Unselect %{label}", %{label: @label}}, @live_resource)}
      >
        <.icon name="hero-x-mark" class="size-4 scale-105 hover:scale-110" />
      </div>
    </div>
    """
  end

  attr :class, :any, default: nil
  attr :show_select_all, :boolean, required: true
  attr :live_resource, :atom, required: true
  attr :field, :any, required: true
  attr :event_target, :any, required: true

  defp multi_select_toggle_all(assigns) do
    ~H"""
    <button
      type="button"
      class={["text-primary text-sm underline hover:cursor-pointer", @class]}
      phx-click="toggle-select-all"
      phx-value-field-name={@field.name}
      phx-target={@event_target}
    >
      <%= if @show_select_all do %>
        {Backpex.__("Select all", @live_resource)}
      <% else %>
        {Backpex.__("Deselect all", @live_resource)}
      <% end %>
    </button>
    """
  end

  attr :class, :any, default: nil
  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :field, :any, required: true
  attr :selected, :list, required: true
  attr :event_target, :any, required: true

  defp multi_select_option(assigns) do
    ~H"""
    <label
      class={["flex space-x-2", @class]}
      phx-click="toggle-option"
      phx-value-id={@value}
      phx-target={@event_target}
    >
      <input
        type="checkbox"
        name={@field.name <> "[]"}
        class="checkbox checkbox-sm checkbox-primary"
        checked={selected?(@value, @selected)}
        checked_value={@value}
        value={@value}
      />
      <span class="text-md cursor-pointer">
        {@label}
      </span>
    </label>
    """
  end

  attr :live_resource, :atom, required: true
  attr :event_target, :any, required: true

  defp multi_select_show_more(assigns) do
    ~H"""
    <button
      type="button"
      class="text-primary mb-2 text-sm underline hover:cursor-pointer"
      phx-click="show-more"
      phx-target={@event_target}
    >
      {Backpex.__("Show more", @live_resource)}
    </button>
    """
  end

  def form_errors?(false, _form), do: false
  def form_errors?(true = _show_errors, form), do: form.errors != []

  def translate_form_errors(errors, translate_error_fun) when is_function(translate_error_fun, 1) do
    errors
    |> Enum.map(fn error ->
      error
      |> translate_error_fun.()
      |> Backpex.translate_error()
    end)
  end

  defp selected?(id, selected), do: Enum.any?(selected, fn {_label, value} -> id == value end)
end
