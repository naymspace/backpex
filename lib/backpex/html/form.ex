defmodule Backpex.HTML.Form do
  @moduledoc """
  Contains all Backpex form components.
  """
  use BackpexWeb, :html

  alias Phoenix.HTML.Form

  @doc """
  Renders an input.
  """
  @doc type: :component

  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file hidden month number password
               range radio search select tel text textarea time url week toggle)

  attr :field, Phoenix.HTML.FormField, doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"

  attr :rest, :global, include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  attr :class, :string, default: nil, doc: "additional class"
  attr :input_class, :string, default: nil, doc: "additional class for the input element"

  attr :input_wrapper_class, :string,
    default: nil,
    doc: "additional class for the input wrapper element, currently only used in select type"

  attr :field_options, :map, default: %{}, doc: "field options map"
  attr :hide_errors, :boolean, default: false, doc: "if errors should be hidden"

  slot :inner_block

  def field_input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, translate_form_errors(field, assigns.field_options))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> field_input()
  end

  def field_input(%{type: "checkbox", value: value} = assigns) do
    assigns = assign_new(assigns, :checked, fn -> Form.normalize_value("checkbox", value) end)

    ~H"""
    <div phx-feedback-for={@name} class={@class}>
      <div class="form-control w-full">
        <%= if @label do %>
          <label class="label cursor-pointer">
            <input type="hidden" name={@name} value="false" />
            <input
              type="checkbox"
              id={@id}
              name={@name}
              value="true"
              checked={@checked}
              class={[
                "checkbox checkbox-sm phx-no-feedback:checkbox phx-no-feedback:checkbox-primary",
                @input_class,
                @errors == [] && "checkbox-primary",
                @errors != [] && "checkbox-error"
              ]}
              {@rest}
            />
            <span class="label-text ml-2"><%= @label %></span>
          </label>
        <% else %>
          <input type="hidden" name={@name} value="false" />
          <input
            type="checkbox"
            id={@id}
            name={@name}
            value="true"
            checked={@checked}
            class={[
              "checkbox checkbox-sm phx-no-feedback:checkbox phx-no-feedback:checkbox-primary",
              @input_class,
              @errors == [] && "checkbox-primary",
              @errors != [] && "checkbox-error"
            ]}
            {@rest}
          />
        <% end %>
      </div>
      <.error :for={msg <- @errors} :if={not @hide_errors}><%= msg %></.error>
    </div>
    """
  end

  def field_input(%{type: "toggle", value: value} = assigns) do
    assigns = assign_new(assigns, :checked, fn -> Form.normalize_value("checkbox", value) end)

    ~H"""
    <div phx-feedback-for={@name} class={@class}>
      <div class="form-control w-full">
        <%= if @label do %>
          <label class="label cursor-pointer">
            <input type="hidden" name={@name} value="false" />
            <input
              type="checkbox"
              id={@id}
              name={@name}
              value="true"
              checked={@checked}
              class={[
                "toggle phx-no-feedback:toggle phx-no-feedback:toggle-primary",
                @input_class,
                @errors == [] && "toggle-primary",
                @errors != [] && "toggle-error"
              ]}
              {@rest}
            />
            <span class="label-text ml-2"><%= @label %></span>
          </label>
        <% else %>
          <input type="hidden" name={@name} value="false" />
          <input
            type="checkbox"
            id={@id}
            name={@name}
            value="true"
            checked={@checked}
            class={[
              "toggle phx-no-feedback:toggle phx-no-feedback:toggle-primary",
              @input_class,
              @errors == [] && "toggle-primary",
              @errors != [] && "toggle-error"
            ]}
            {@rest}
          />
        <% end %>
      </div>
      <.error :for={msg <- @errors} :if={not @hide_errors}><%= msg %></.error>
    </div>
    """
  end

  def field_input(%{type: "select"} = assigns) do
    ~H"""
    <div phx-feedback-for={@name} class={@class}>
      <div class="form-control">
        <label :if={@label} class="label">
          <span class="label-text"><%= @label %></span>
        </label>
        <div class={[
          @input_wrapper_class,
          "phx-no-feedback:[&>*]:select phx-no-feedback:[&>*]:select-bordered phx-no-feedback:[&>*]:text-gray-900",
          @errors == [] && "[&>*]:select [&>*]:select-bordered [&>*]:text-gray-900",
          @errors != [] && "[&>*]:select [&>*]:select-error [&>*]:bg-red-50 [&>*]:text-red-800"
        ]}>
          <select class={["w-full", @input_class]} name={@name} {@rest}>
            <option :if={@prompt} value=""><%= @prompt %></option>
            <%= Phoenix.HTML.Form.options_for_select(@options, @value) %>
          </select>
        </div>
      </div>
      <.error :for={msg <- @errors} :if={not @hide_errors}><%= msg %></.error>
    </div>
    """
  end

  def field_input(%{type: "textarea"} = assigns) do
    ~H"""
    <div phx-feedback-for={@name} class={@class}>
      <div class="form-control">
        <label :if={@label} class="label">
          <span class="label-text"><%= @label %></span>
        </label>
        <textarea
          id={@id}
          name={@name}
          class={[
            "textarea phx-no-feedback:textarea phx-no-feedback:textarea-bordered",
            @input_class,
            @errors == [] && "textarea-bordered",
            @errors != [] && "textarea-error bg-red-50"
          ]}
          {@rest}
        ><%= Phoenix.HTML.Form.normalize_value("textarea", @value) %></textarea>
      </div>
      <.error :for={msg <- @errors} :if={not @hide_errors}><%= msg %></.error>
    </div>
    """
  end

  def field_input(assigns) do
    ~H"""
    <div phx-feedback-for={@name} class={@class}>
      <div class="form-control">
        <label :if={@label} class="label">
          <span class="label-text"><%= @label %></span>
        </label>
        <input
          type={@type}
          name={@name}
          id={@id}
          value={Phoenix.HTML.Form.normalize_value(@type, @value)}
          class={[
            "input phx-no-feedback:input phx-no-feedback:input-bordered",
            @input_class,
            @errors == [] && "input-bordered",
            @errors != [] && "input-error bg-red-50"
          ]}
          placeholder={Backpex.Field.placeholder(@field_options, assigns)}
          phx-debounce={Backpex.Field.debounce(@field_options, assigns)}
          phx-throttle={Backpex.Field.throttle(@field_options, assigns)}
          {@rest}
        />
      </div>
      <.error :for={msg <- @errors} :if={not @hide_errors}><%= msg %></.error>
    </div>
    """
  end

  @doc """
  Generates a generic error message.
  """
  slot(:inner_block, required: true)

  def error(assigns) do
    ~H"""
    <p class="mt-1 text-xs italic text-red-500 phx-no-feedback:hidden">
      <%= render_slot(@inner_block) %>
    </p>
    """
  end

  @doc """
  Renders a searchable multi select.
  """
  @doc type: :component
  attr(:prompt, :string, required: true, doc: "string that will be shown when no option is selected")
  attr(:not_found_text, :string, required: true, doc: "string that will be shown when there are no options")
  attr(:options, :list, required: true, doc: "a list of options for the select")
  attr(:search_input, :string, required: true, doc: "to prefill and or persist the search term for rerendering")
  attr(:event_target, :any, required: true, doc: "the target that handles the events of this component")
  attr(:field_options, :map, required: true, doc: "field options for the corresponding field")
  attr(:field, :any, required: true, doc: "form field the select should be for")
  attr(:selected, :list, required: true, doc: "the selected values")
  attr(:show_select_all, :boolean, required: true, doc: "whether to display the select all button")
  attr(:show_more, :boolean, required: true, doc: "whether there are more options to show")
  attr(:search_event, :string, default: "search", doc: "the event that will be sent when the search input changes")
  attr(:hide_errors, :boolean, default: false, doc: "if errors should be hidden")

  def multi_select(assigns) do
    assigns = assign(assigns, :errors, translate_form_errors(assigns.field, assigns.field_options))

    ~H"""
    <div class="dropdown w-full">
      <label tabindex="0" class="input input-bordered block h-fit w-full p-2">
        <div class="flex h-full w-full flex-wrap items-center gap-1 px-2">
          <p :if={@selected == []} class="p-0.5 text-sm text-gray-900">
            <%= @prompt %>
          </p>

          <div :for={{label, value} <- @selected} class="badge badge-primary p-[11px]">
            <p class="mr-1">
              <%= label %>
            </p>

            <div
              role="button"
              phx-click="toggle-option"
              phx-value-id={value}
              phx-target={@event_target}
              aria-label={Backpex.translate({"Unselect %{label}", %{label: label}})}
            >
              <Heroicons.x_mark class="ml-1 h-4 w-4 text-white" />
            </div>
          </div>
        </div>
      </label>
      <.error :for={msg <- @errors} :if={not @hide_errors}><%= msg %></.error>
      <div tabindex="0" class="dropdown-content z-[1] menu bg-base-100 rounded-box w-full overflow-y-auto shadow">
        <div class="max-h-72 p-2">
          <input
            type="search"
            name={@field.name <> "_search"}
            class="input input-sm input-bordered mb-2 w-full"
            placeholder={Backpex.translate("Search")}
            value={@search_input}
            phx-change={@search_event}
            phx-target={@event_target}
          />
          <p :if={@options == []} class="w-full">
            <%= @not_found_text %>
          </p>

          <button
            :if={Enum.any?(@options)}
            type="button"
            class="text-primary my-2 text-sm underline hover:cursor-pointer"
            phx-click="toggle-select-all"
            phx-value-field-name={@field.name}
            phx-target={@event_target}
          >
            <%= if @show_select_all do %>
              <%= Backpex.translate("Select all") %>
            <% else %>
              <%= Backpex.translate("Deselect all") %>
            <% end %>
          </button>

          <input type="hidden" name={@field.name} value="" />

          <div class="my-2 w-full">
            <div
              :for={{label, value} <- @options}
              class="mt-2 flex space-x-2"
              phx-click="toggle-option"
              phx-value-id={value}
              phx-target={@event_target}
            >
              <input
                type="checkbox"
                name={@field.name<> "[]"}
                class="checkbox checkbox-sm checkbox-primary"
                checked={selected?(value, @selected)}
                checked_value={value}
                value={value}
              />
              <p class="text-md cursor-pointer">
                <%= label %>
              </p>
            </div>
          </div>

          <button
            :if={@show_more}
            type="button"
            class="text-primary mb-2 text-sm underline hover:cursor-pointer"
            phx-click="show-more"
            phx-target={@event_target}
          >
            <%= Backpex.translate("Show more") %>
          </button>
        </div>
      </div>
    </div>
    """
  end

  def form_errors?(false, _form), do: false
  def form_errors?(true = _show_errors, form), do: form.errors != []

  defp translate_form_errors(form_field, field_options) do
    translator_func =
      case field_options do
        %{translate_error: translate_error} = _field_options ->
          fn error -> translate_error.(error) end

        _field_options ->
          &Function.identity/1
      end

    Enum.map(form_field.errors, fn error -> translator_func.(error) |> Backpex.translate(:error) end)
  end

  defp selected?(id, selected), do: Enum.any?(selected, fn {_label, value} -> id == value end)
end
