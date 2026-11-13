defmodule Backpex.HTML.Combobox do
  @moduledoc """
  A select with search, multiple selection, groups and custom option markup.

  `combobox/1` is a form control: it takes a `Phoenix.HTML.FormField` (or `name` and `value`), takes part in
  `phx-change` and submit like a native `<select>` and needs no event handlers on the server for local options. The
  behaviour in the browser comes from the `BackpexCombobox` hook, which ships with the Backpex hooks.

  ## Usage

  A single select with a label:

      <.combobox field={@form[:country]} label="Country" options={@countries} />

  A multiple select with at most three values and a clear button:

      <.combobox
        field={@form[:tags]}
        label="Tags"
        options={[{"Elixir", "elixir"}, {"Phoenix", "phoenix"}]}
        multiple
        max={3}
        clearable
      />

  Without a field, `id` is required and `name` and `value` are passed explicitly:

      <.combobox id="status" name="status" value={@status} label="Status" options={~w(draft published)} />

  Give every combobox a `label` or an `aria-label`: the listbox of the popup has no other accessible name.

  ## Options

  `options` accepts everything `Phoenix.HTML.Form.options_for_select/2` accepts, so a combobox is a drop-in for a
  select input:

    * `"Label"`, an atom or a number: the label is the value
    * `{label, value}`, which includes keyword lists like `[Admin: "admin"]` and maps like `%{"Admin" => "admin"}`
    * a keyword list or map with `:key` (or `:label`) and `:value`, an optional `:disabled` and any other keys
    * a group `{group_label, options}` with options in one of the formats above

  Each option is normalized to a map with `:label`, `:value` (both strings) and `:disabled`, merged with the extra keys
  of a keyword list or map option. Values are compared as strings, so `value={1}` selects the option with value `"1"`.

  ## Slots

    * `:option` renders the content of an option. It receives the normalized option map, so extra keys are available:

          <.combobox field={@form[:user_id]} label="User" options={@users}>
            <:option :let={user}>
              <span class="font-medium">{user.label}</span>
              <span class="text-base-content/60 text-xs">{user.email}</span>
            </:option>
          </.combobox>

    * `:header` and `:footer` are pinned above and below the scrolling list of options inside the popup.
    * `:empty` replaces `no_results_text` when no option matches.

  The selected value and the badges always show the label, not the `:option` slot.

  ## Server search

  By default the popup filters the rendered options in the browser (case and diacritics insensitive). With
  `on_search`, it pushes an event instead and the server renders the matching options:

      <.combobox
        id="user-select"
        name="user_id"
        value={@user_id}
        label="User"
        options={@user_options}
        selected_options={@selected_user_options}
        on_search="search_users"
        phx-target={@myself}
      />

      def handle_event("search_users", %{"query" => query, "id" => "user-select"}, socket) do
        {:noreply, assign(socket, :user_options, search_users(query))}
      end

  The event is pushed `search_debounce` milliseconds after the last keystroke, to `phx-target` when it is set. It is
  pushed with an empty query when the popup closes after a search. While it is pending, the root element has a
  `data-loading` attribute and the search input shows a spinner.

  Pass the options of the current value in `selected_options`, as they may not be in the search results. A selected
  value that is in neither list is shown as is.

  ## Commands and events

  The hook listens on the root element (the element with the combobox's `id`) for these DOM events, so other elements
  can control the combobox with `Phoenix.LiveView.JS.dispatch/2`:

    * `combobox:open` and `combobox:close`
    * `combobox:clear` removes the selection
    * `combobox:select-all` selects every enabled option that the search currently shows, up to `max` (`multiple`
      only)

  A button in the `:header` or `:footer` slot dispatches to its own combobox without `:to`, as the event bubbles to the
  root:

      <:header>
        <button type="button" class="btn btn-ghost btn-xs" phx-click={JS.dispatch("combobox:select-all")}>
          Select all
        </button>
      </:header>

  After every change by the user the root dispatches a bubbling `combobox:change` event with the new value in
  `event.detail.value`: a string, or a list of strings for `multiple`.

  ## Form integration

  The combobox renders these form controls:

    * an *anchor* input with the plain `name`. It is a hidden text input, not `type="hidden"`. For a single select it
      holds the value, for `multiple` it holds an empty string, so that the field is submitted when nothing is selected
    * for `multiple`, one `type="hidden"` input named `name[]` per selected value

  After every change the hook dispatches `input` and `change` events on the anchor input. LiveView then sends the
  form's `phx-change` event with `_target` set to the field name. LiveView marks fields whose inputs are all of type
  `hidden` as used from the start, so the anchor input is a text input: like other inputs, the field counts as unused,
  and `field` shows no errors, until the user changed the combobox (see `Phoenix.Component.used_input?/1`).

  The hook changes the selection in the browser right away and takes the value the server renders whenever a patch
  changes it. A form that tracks its params with `phx-change`, as usual, therefore keeps the selection across patches,
  and a `phx-change` handler that replaces the chosen value with another one shows that value. Like a native input, the
  combobox keeps the admin's choice when the server renders the same value as before, since such a patch does not
  touch the field.

  A `disabled` combobox puts `disabled` on its inputs, so the value is not submitted. A `readonly` combobox still
  submits its value. Neither renders the popup or the hook. A `form` attribute is passed on to the inputs.
  """
  use BackpexWeb, :html

  import Backpex.HTML.CoreComponents, only: [icon: 1]
  import Backpex.HTML.Form, only: [error: 1, help_text: 1]

  alias Backpex.HTML.Form
  alias Phoenix.HTML.FormField

  require Backpex

  @doc """
  Renders a combobox.

  See the module documentation for the options formats, slots, server search and the events.
  """
  @doc type: :component

  attr :id, :any, default: nil, doc: "DOM id of the combobox, defaults to the id of `field`; required without `field`"
  attr :name, :any, doc: "name of the form field; `multiple` submits the values as `name[]`"
  attr :value, :any, doc: "the selected value, or a list of values for `multiple`"
  attr :field, FormField, doc: "a form field struct retrieved from the form, for example: @form[:country]"

  attr :label, :string, default: nil
  attr :help_text, :string, default: nil
  attr :errors, :list, default: []

  attr :options, :list, required: true, doc: "the options, see the module documentation"

  attr :selected_options, :list,
    default: nil,
    doc: "options for the current value that may be missing from `options`, e.g. with server search"

  attr :multiple, :boolean, default: false
  attr :max, :integer, default: nil, doc: "maximum number of selected values (`multiple` only)"

  attr :searchable, :boolean, default: true, doc: "whether the popup has a search input"

  attr :search_threshold, :integer,
    default: 0,
    doc: "hide the search input while there are fewer options than this; ignored with `on_search`"

  attr :on_search, :string, default: nil, doc: "event pushed with the query instead of filtering in the browser"
  attr :search_debounce, :integer, default: 300, doc: "milliseconds before `on_search` is pushed"

  attr :clearable, :boolean, default: false, doc: "whether a button clears the selection"

  attr :placeholder, :string, default: nil, doc: "shown when nothing is selected"
  attr :search_placeholder, :string, default: nil, doc: "placeholder and accessible name of the search input"
  attr :no_results_text, :string, default: nil, doc: "shown when no option matches, unless the `:empty` slot is given"
  attr :clear_label, :string, default: nil, doc: "accessible name of the clear button"

  attr :disabled, :boolean, default: false, doc: "not interactive, and the value is not submitted"
  attr :readonly, :boolean, default: false, doc: "not interactive, but the value is submitted"

  attr :size, :string, default: "md", values: ~w(xs sm md lg xl)

  attr :class, :any, default: nil, doc: "additional classes for the container element"
  attr :input_class, :any, default: nil, doc: "the classes of the control to use over defaults"
  attr :error_class, :any, default: nil, doc: "the error classes of the control to use over defaults"

  attr :popup_class, :any,
    default: nil,
    doc: "additional classes for the popup; they replace its default maximum height `max-h-80`"

  attr :translate_error_fun, :any, default: &Function.identity/1, doc: "a custom function to map form errors"
  attr :hide_errors, :boolean, default: false, doc: "if errors should be hidden"
  attr :live_resource, :atom, default: nil, doc: "the LiveResource used to translate the default texts"

  attr :rest, :global,
    include: ~w(form),
    doc: "attributes for the root element; `aria-*` go to the trigger button and `form` to the inputs"

  slot :option, doc: "custom content of an option, receives the normalized option map"
  slot :header, doc: "content pinned above the options in the popup"
  slot :footer, doc: "content pinned below the options in the popup"
  slot :empty, doc: "shown when no option matches"

  def combobox(%{field: %FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Form.translate_form_errors(errors, assigns.translate_error_fun))
    |> assign_new(:name, fn -> field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> combobox()
  end

  def combobox(%{id: nil}) do
    raise ArgumentError, "Backpex.HTML.Combobox.combobox/1 requires an id when no field is given"
  end

  def combobox(assigns) do
    assigns =
      assigns
      |> assign_new(:name, fn -> nil end)
      |> assign_new(:value, fn -> nil end)

    entries = index_entries(normalize_options(assigns.options))
    options = flat_options(entries)
    selected_values = selected_values(assigns.value, assigns.multiple)
    lookup = option_lookup(options, assigns.selected_options)
    {aria, rest} = Map.split_with(assigns.rest, fn {key, _value} -> String.starts_with?("#{key}", "aria-") end)
    {form, rest} = Map.pop(rest, :form)
    label_ids = (assigns.label && "#{assigns.id}-label") || aria[:"aria-labelledby"]
    aria_label = aria[:"aria-label"]

    assigns
    |> assign(:entries, entries)
    |> assign(:selected_values, selected_values)
    |> assign(:selected, Enum.map(selected_values, &Map.get(lookup, &1, %{label: &1, value: &1, disabled: false})))
    |> assign(:max_reached, assigns.multiple and is_integer(assigns.max) and length(selected_values) >= assigns.max)
    |> assign(:interactive, not assigns.disabled and not assigns.readonly)
    |> assign(:show_search, show_search?(assigns, length(options)))
    |> assign(:form, form)
    |> assign(:root_rest, rest)
    |> assign(:trigger_rest, Map.drop(aria, [:"aria-labelledby", :"aria-label", :"aria-describedby"]))
    |> assign(:label_ids, label_ids)
    |> assign(:aria_label, aria_label)
    |> assign(:trigger_labelledby, trigger_labelledby(assigns.id, label_ids, aria_label))
    |> assign(:describedby, describedby(assigns, aria[:"aria-describedby"]))
    |> assign_texts()
    |> render_combobox()
  end

  defp render_combobox(assigns) do
    ~H"""
    <div class={["fieldset py-0", @class]}>
      <label :if={@label} id={"#{@id}-label"} for={"#{@id}-trigger"} class="label mb-1">{@label}</label>
      <div
        id={@id}
        data-part="root"
        phx-hook={@interactive && "BackpexCombobox"}
        data-multiple={@multiple}
        data-max={@multiple && @max}
        data-on-search={@on_search}
        data-search-debounce={@on_search && @search_debounce}
        class="group/combobox relative"
        {@root_rest}
      >
        <div data-part="inputs">
          <%!--
            Not type="hidden": LiveView treats a field whose inputs are all hidden as used from the start, so its errors
            would show before the user changed the combobox.
          --%>
          <input
            type="text"
            hidden
            data-part="anchor"
            name={@name}
            value={if @multiple, do: "", else: List.first(@selected_values, "")}
            tabindex="-1"
            aria-hidden="true"
            autocomplete="off"
            disabled={@disabled}
            form={@form}
          />
          <input
            :for={value <- @selected_values}
            :if={@multiple}
            type="hidden"
            name={@name && @name <> "[]"}
            value={value}
            disabled={@disabled}
            form={@form}
          />
        </div>

        <div
          data-part="control"
          class={[
            "relative flex items-center gap-1",
            @input_class || ["input h-auto min-h-(--size) w-full", control_padding_class(@size)],
            size_class(@size),
            @interactive && "cursor-pointer",
            @readonly && "cursor-default",
            @disabled && "cursor-not-allowed",
            Form.readonly_input_class(not @interactive),
            @errors != [] && (@error_class || "input-error border-error bg-error/10")
          ]}
        >
          <div id={"#{@id}-value"} data-part="value" class="flex min-w-0 flex-1 flex-wrap items-center gap-1">
            <span data-part="placeholder" class="text-base-content/50 truncate" hidden={@selected != []}>
              {@placeholder}
            </span>
            <span :if={not @multiple} data-part="value-label" class="truncate" hidden={@selected == []}>{selected_label(
              @selected
            )}</span>
            <%!--
              The badges are plain elements, not function components: LiveView marks the root of a function component
              with an id and, when it is unchanged, skips it in a patch, expecting to find it in the DOM. The hook adds
              and removes badges, so such an id could point to a badge the hook removed and leave an empty element.
              Keep this markup in sync with the badge template below.
            --%>
            <span
              :for={option <- @selected}
              :if={@multiple}
              data-part="badge"
              data-value={option.value}
              class={badge_class(@size, @interactive)}
            >
              <span data-part="badge-label" class="truncate">{option.label}</span>
              <span :if={@interactive} data-part="badge-remove" aria-hidden="true" class={badge_remove_class()}>
                <span class={badge_remove_icon_class()}></span>
              </span>
            </span>
          </div>
          <%!--
            The trigger covers the whole control, so a click anywhere on it opens the popup. It stays empty, because the
            badges and the clear button are interactive and must not be nested in a button; its accessible name is the
            label followed by the value.
          --%>
          <button
            id={"#{@id}-trigger"}
            type="button"
            role="combobox"
            data-part="trigger"
            aria-haspopup="listbox"
            aria-expanded="false"
            aria-controls={@interactive && "#{@id}-listbox"}
            aria-labelledby={@trigger_labelledby}
            aria-label={@aria_label}
            aria-describedby={@describedby}
            aria-invalid={@errors != [] && "true"}
            aria-readonly={@readonly && "true"}
            disabled={@disabled}
            class="rounded-field absolute inset-0 cursor-[inherit] outline-none"
            {@trigger_rest}
          ></button>
          <button
            :if={@clearable and @interactive}
            type="button"
            data-part="clear"
            aria-label={@clear_label}
            hidden={@selected == []}
            class={["btn btn-ghost btn-circle btn-xs relative z-1 shrink-0", clear_size_class(@size)]}
          >
            <.icon name="hero-x-mark" class={clear_icon_size_class(@size)} />
          </button>
          <.icon
            :if={@interactive}
            name="hero-chevron-up-down"
            class="pointer-events-none size-4 shrink-0 opacity-60"
          />
        </div>

        <%!--
          A manual popover sits in the top layer while open, so no overflow container, table or modal clips it. It is
          flex only while open (`open:`), as a display class would override the browser's style that hides a closed
          popover.
        --%>
        <div
          :if={@interactive}
          id={"#{@id}-popup"}
          data-part="popup"
          popover="manual"
          class={[
            "rounded-box border-base-300 bg-base-100 text-base-content fixed inset-auto m-0 flex-col overflow-hidden border p-0 shadow-lg open:flex",
            @popup_class || "max-h-80"
          ]}
        >
          <div :for={header <- @header} class="border-base-200 border-b p-2">{render_slot(header)}</div>
          <div :if={@show_search} class="p-2 pb-1">
            <label class={["input w-full", search_size_class(@size)]}>
              <.icon name="hero-magnifying-glass" class="size-4 shrink-0 opacity-60" />
              <input
                id={"#{@id}-search"}
                type="text"
                data-part="search"
                role="combobox"
                aria-autocomplete="list"
                aria-expanded="false"
                aria-controls={"#{@id}-listbox"}
                aria-label={@search_placeholder}
                placeholder={@search_placeholder}
                autocomplete="off"
                spellcheck="false"
              />
              <span
                class="loading loading-spinner loading-xs group-data-loading/combobox:inline-block hidden shrink-0"
                aria-hidden="true"
              ></span>
            </label>
          </div>
          <div
            id={"#{@id}-listbox"}
            data-part="listbox"
            role="listbox"
            aria-multiselectable={@multiple && "true"}
            aria-labelledby={@label_ids}
            aria-label={!@label_ids && @aria_label}
            class={["min-h-0 overflow-y-auto overscroll-contain p-1", option_text_class(@size)]}
          >
            <%= for entry <- @entries do %>
              <%= case entry do %>
                <% {:group, group_index, group_label, group_options} -> %>
                  <div
                    role="group"
                    data-part="group"
                    aria-labelledby={"#{@id}-group-#{group_index}-label"}
                    class="not-first:mt-1"
                  >
                    <div
                      id={"#{@id}-group-#{group_index}-label"}
                      role="presentation"
                      data-part="group-label"
                      class="text-base-content/60 px-2 pt-2 pb-1 text-xs font-semibold"
                    >
                      {group_label}
                    </div>
                    <.combobox_option
                      :for={{index, option} <- group_options}
                      id={"#{@id}-option-#{index}"}
                      option={option}
                      multiple={@multiple}
                      selected={option.value in @selected_values}
                      max_reached={@max_reached}
                      content={@option}
                    />
                  </div>
                <% {:option, index, option} -> %>
                  <.combobox_option
                    id={"#{@id}-option-#{index}"}
                    option={option}
                    multiple={@multiple}
                    selected={option.value in @selected_values}
                    max_reached={@max_reached}
                    content={@option}
                  />
              <% end %>
            <% end %>
          </div>
          <div
            data-part="empty"
            hidden={@entries != []}
            class={["text-base-content/60 px-3 py-2", option_text_class(@size)]}
          >
            <%= if @empty != [] do %>
              {render_slot(@empty)}
            <% else %>
              {@no_results_text}
            <% end %>
          </div>
          <div :for={footer <- @footer} class="border-base-200 border-t p-2">{render_slot(footer)}</div>
        </div>

        <%!--
          The hook clones this badge for a new value, so the server renders the badges of the selection exactly as the
          hook does and the patch after a change does not alter them.
        --%>
        <template :if={@multiple and @interactive} data-part="badge-template">
          <span data-part="badge" data-value="" class={badge_class(@size, true)}>
            <span data-part="badge-label" class="truncate"></span>
            <span data-part="badge-remove" aria-hidden="true" class={badge_remove_class()}>
              <span class={badge_remove_icon_class()}></span>
            </span>
          </span>
        </template>
      </div>
      <div :if={@errors != [] and not @hide_errors} id={"#{@id}-errors"}>
        <.error :for={msg <- @errors}>{msg}</.error>
      </div>
      <.help_text :if={@help_text} id={"#{@id}-help"}>{@help_text}</.help_text>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :option, :map, required: true
  attr :multiple, :boolean, required: true
  attr :selected, :boolean, required: true
  attr :max_reached, :boolean, required: true
  attr :content, :list, required: true

  defp combobox_option(assigns) do
    ~H"""
    <div
      id={@id}
      role="option"
      data-part="option"
      data-value={@option.value}
      data-label={@option.label}
      data-disabled={@option.disabled}
      aria-selected={to_string(@selected)}
      aria-disabled={(@option.disabled or (@max_reached and not @selected)) && "true"}
      class="rounded-field group/option data-active:bg-base-200 flex cursor-pointer select-none items-center gap-2 px-2 py-1.5 aria-disabled:cursor-not-allowed aria-disabled:opacity-50"
    >
      <span
        :if={@multiple}
        class="rounded-selector border-base-content/30 group-aria-selected/option:border-primary group-aria-selected/option:bg-primary group-aria-selected/option:text-primary-content flex size-4 shrink-0 items-center justify-center border"
      >
        <.icon name="hero-check" class="group-aria-selected/option:visible invisible size-3" />
      </span>
      <span class="min-w-0 flex-1">
        <%= if @content != [] do %>
          {render_slot(@content, @option)}
        <% else %>
          {@option.label}
        <% end %>
      </span>
      <.icon
        :if={not @multiple}
        name="hero-check"
        class="text-primary group-aria-selected/option:visible invisible size-4 shrink-0"
      />
    </div>
    """
  end

  # A badge's remove control is a mouse shortcut, hidden from assistive technology: keyboard and screen reader users
  # deselect in the listbox or with Backspace on the trigger. It is not focusable, and the hook keeps a click on it from
  # moving focus.
  defp badge_class(size, removable) do
    [
      "badge badge-soft h-auto min-h-(--size) max-w-full gap-0.5",
      badge_size_class(size),
      if(removable, do: "badge-primary pr-1", else: "badge-neutral")
    ]
  end

  defp badge_remove_class, do: "relative z-1 flex cursor-pointer items-center opacity-70 hover:opacity-100"

  defp badge_remove_icon_class, do: "hero-x-mark size-3.5"

  defp assign_texts(assigns) do
    live_resource = assigns.live_resource

    default_placeholder =
      if assigns.multiple,
        do: Backpex.__("Select options...", live_resource),
        else: Backpex.__("Select an option...", live_resource)

    assigns
    |> assign(:placeholder, assigns.placeholder || default_placeholder)
    |> assign(:search_placeholder, assigns.search_placeholder || Backpex.__("Search", live_resource))
    |> assign(:no_results_text, assigns.no_results_text || Backpex.__("No options found", live_resource))
    |> assign(:clear_label, assigns.clear_label || Backpex.__("Clear selection", live_resource))
  end

  defp show_search?(%{searchable: false}, _count), do: false
  defp show_search?(%{on_search: event}, _count) when is_binary(event), do: true
  defp show_search?(%{search_threshold: threshold}, count), do: count >= threshold

  defp trigger_labelledby(id, nil, nil), do: "#{id}-value"
  defp trigger_labelledby(id, nil, _aria_label), do: "#{id}-trigger #{id}-value"
  defp trigger_labelledby(id, label_ids, _aria_label), do: "#{label_ids} #{id}-value"

  defp describedby(assigns, extra) do
    errors_shown? = assigns.errors != [] and not assigns.hide_errors

    ids = [
      errors_shown? && "#{assigns.id}-errors",
      assigns.help_text && "#{assigns.id}-help",
      extra
    ]

    case Enum.filter(ids, & &1) do
      [] -> nil
      ids -> Enum.join(ids, " ")
    end
  end

  defp selected_label([option | _rest]), do: option.label
  defp selected_label([]), do: ""

  # Full literal class names, so Tailwind finds them in the source.
  defp size_class("xs"), do: "input-xs"
  defp size_class("sm"), do: "input-sm"
  defp size_class("md"), do: "input-md"
  defp size_class("lg"), do: "input-lg"
  defp size_class("xl"), do: "input-xl"

  # The padding and the clear button fit into the height of a daisyUI input of the same size, so the control is as high
  # as an input and keeps its height when the selection changes. Badges may wrap and make it higher.
  defp control_padding_class("xs"), do: "py-0.5"
  defp control_padding_class(_size), do: "py-1"

  defp clear_size_class("xs"), do: "size-4"
  defp clear_size_class("sm"), do: "size-5"
  defp clear_size_class("md"), do: "size-6"
  defp clear_size_class("lg"), do: "size-7"
  defp clear_size_class("xl"), do: "size-8"

  defp clear_icon_size_class(size) when size in ~w(xs sm), do: "size-3"
  defp clear_icon_size_class(size) when size in ~w(md lg), do: "size-4"
  defp clear_icon_size_class("xl"), do: "size-5"

  defp search_size_class(size) when size in ~w(xs sm), do: "input-xs"
  defp search_size_class(size) when size in ~w(md lg), do: "input-sm"
  defp search_size_class("xl"), do: "input-md"

  defp badge_size_class(size) when size in ~w(xs sm), do: "badge-xs"
  defp badge_size_class("md"), do: "badge-sm"
  defp badge_size_class("lg"), do: "badge-md"
  defp badge_size_class("xl"), do: "badge-lg"

  defp option_text_class(size) when size in ~w(xs sm), do: "text-xs"
  defp option_text_class("md"), do: "text-sm"
  defp option_text_class("lg"), do: "text-base"
  defp option_text_class("xl"), do: "text-lg"

  defp selected_values(value, true = _multiple) do
    value
    |> List.wrap()
    |> Enum.map(&stringify/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp selected_values(value, false = _multiple) do
    value |> List.wrap() |> List.first() |> stringify() |> List.wrap() |> Enum.reject(&(&1 == ""))
  end

  defp option_lookup(options, selected_options) do
    selected =
      (selected_options || [])
      |> normalize_options()
      |> index_entries()
      |> flat_options()

    Map.new(options ++ selected, &{&1.value, &1})
  end

  defp flat_options(entries) do
    Enum.flat_map(entries, fn
      {:group, _index, _label, options} -> Enum.map(options, fn {_index, option} -> option end)
      {:option, _index, option} -> [option]
    end)
  end

  # Numbers the options across groups, as their DOM ids are index-based: values may contain characters that are not
  # valid in an id.
  defp index_entries(entries) do
    {indexed, _counts} =
      Enum.map_reduce(entries, {0, 0}, fn
        {:group, label, options}, {index, group_index} ->
          indexed = Enum.with_index(options, fn option, offset -> {index + offset, option} end)
          {{:group, group_index, label, indexed}, {index + length(options), group_index + 1}}

        {:option, option}, {index, group_index} ->
          {{:option, index, option}, {index + 1, group_index}}
      end)

    indexed
  end

  defp normalize_options(options) when is_map(options), do: options |> Enum.to_list() |> normalize_options()

  defp normalize_options(options) when is_list(options) do
    Enum.flat_map(options, fn
      :hr -> []
      {:hr, nil} -> []
      {label, group} when is_list(group) or (is_map(group) and not is_struct(group)) -> [group(label, group)]
      option -> [{:option, normalize_option(option)}]
    end)
  end

  defp group(label, options) do
    options =
      options
      |> normalize_options()
      |> Enum.flat_map(fn
        {:option, option} -> [option]
        {:group, _label, options} -> options
      end)

    {:group, to_string(label), options}
  end

  defp normalize_option(option) when is_list(option), do: option |> Map.new() |> normalize_option()

  defp normalize_option(%{value: value} = option) when not is_struct(option) do
    label = Map.get(option, :key, Map.get(option, :label))

    if is_nil(label) do
      raise ArgumentError, "expected a :key or :label in combobox option #{inspect(option)}"
    end

    option
    |> Map.delete(:key)
    |> Map.merge(%{label: stringify(label), value: stringify(value), disabled: Map.get(option, :disabled) == true})
  end

  defp normalize_option({label, value}), do: %{label: stringify(label), value: stringify(value), disabled: false}

  defp normalize_option(option) when is_binary(option) or is_atom(option) or is_number(option) do
    %{label: stringify(option), value: stringify(option), disabled: false}
  end

  defp normalize_option(option) do
    raise ArgumentError, "invalid combobox option #{inspect(option)}"
  end

  defp stringify(nil), do: ""
  defp stringify(value), do: to_string(value)
end
