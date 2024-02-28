defmodule Backpex.HTML.Form do
  @moduledoc """
  Contains all Backpex form components.
  """
  use BackpexWeb, :html

  alias Phoenix.HTML.Form, as: PhoenixForm

  @doc """
  Renders an input.
  """
  @doc type: :component

  attr(:form, :atom, required: true, doc: "the form")
  attr(:field_name, :atom, required: true, doc: "the field name")
  attr(:field_options, :map, required: true, doc: "the field options")
  attr(:options, :list, doc: "the options to be used for a select input")
  attr(:value, :any, doc: "the value of the form input")

  attr(:type, :string,
    required: true,
    values: ~w(text textarea toggle number date datetime-local select)
  )

  attr(:rest, :global, include: ~w(readonly disabled min step))

  def field_input(%{type: "text"} = assigns) do
    assigns =
      assigns
      |> assign_new(:errors, fn -> Keyword.get_values(assigns.form.errors || [], assigns.field_name) end)

    ~H"""
    <div phx-feedback-for={PhoenixForm.input_name(@form, @field_name)}>
      <%= PhoenixForm.text_input(
        @form,
        @field_name,
        [
          class: [
            "phx-no-feedback:input phx-no-feedback:input-bordered w-full",
            @errors == [] && "input input-bordered",
            @errors != [] && "input input-error bg-red-50 placeholder-danger"
          ],
          placeholder: Backpex.Field.placeholder(@field_options, assigns),
          phx_debounce: Backpex.Field.debounce(@field_options, assigns),
          phx_throttle: Backpex.Field.throttle(@field_options, assigns)
        ] ++ Map.to_list(@rest)
      ) %>
      <.error_tag form={@form} name={@field_name} field_options={@field_options} />
    </div>
    """
  end

  def field_input(%{type: "textarea"} = assigns) do
    assigns =
      assigns
      |> assign_new(:errors, fn -> Keyword.get_values(assigns.form.errors || [], assigns.field_name) end)

    ~H"""
    <div phx-feedback-for={PhoenixForm.input_name(@form, @field_name)}>
      <%= PhoenixForm.textarea(
        @form,
        @field_name,
        [
          class: [
            "phx-no-feedback:textarea phx-no-feedback:textarea-bordered w-full",
            @errors == [] && "textarea textarea-bordered",
            @errors != [] && "textarea textarea-error bg-red-50 placeholder-danger"
          ],
          placeholder: Backpex.Field.placeholder(@field_options, assigns),
          phx_debounce: Backpex.Field.debounce(@field_options, assigns),
          phx_throttle: Backpex.Field.throttle(@field_options, assigns)
        ] ++ Map.to_list(@rest)
      ) %>
      <.error_tag form={@form} name={@field_name} field_options={@field_options} />
    </div>
    """
  end

  def field_input(%{type: "toggle"} = assigns) do
    ~H"""
    <div phx-feedback-for={PhoenixForm.input_name(@form, @field_name)}>
      <%= PhoenixForm.checkbox(
        @form,
        @field_name,
        [
          class: "toggle toggle-primary"
        ] ++ Map.to_list(@rest)
      ) %>
      <.error_tag form={@form} name={@field_name} field_options={@field_options} />
    </div>
    """
  end

  def field_input(%{type: "select"} = assigns) do
    rest = if Map.get(assigns, :value), do: Map.put(assigns.rest, :value, assigns.value), else: assigns.rest

    assigns =
      assigns
      |> assign(:rest, rest)
      |> assign_new(:errors, fn -> Keyword.get_values(assigns.form.errors || [], assigns.field_name) end)

    ~H"""
    <div phx-feedback-for={PhoenixForm.input_name(@form, @field_name)}>
      <div class={[
        "[&>*]:w-full phx-no-feedback:[&>*]:select phx-no-feedback:[&>*]:select-bordered phx-no-feedback:[&>*]:text-gray-900",
        @errors == [] && "[&>*]:select [&>*]:select-bordered [&>*]:text-gray-900",
        @errors != [] && "[&>*]:select [&>*]:select-error [&>*]:bg-red-50 [&>*]:text-red-800"
      ]}>
        <%= PhoenixForm.select(
          @form,
          @field_name,
          @options,
          Map.to_list(@rest)
        ) %>
      </div>
      <.error_tag form={@form} name={@field_name} field_options={@field_options} />
    </div>
    """
  end

  def field_input(assigns) do
    assigns =
      assigns
      |> assign_new(:errors, fn -> Keyword.get_values(assigns.form.errors || [], assigns.field_name) end)
      |> assign_new(:value, fn -> get_value(assigns.form, assigns.field_name) end)

    ~H"""
    <div phx-feedback-for={PhoenixForm.input_name(@form, @field_name)}>
      <input
        id={PhoenixForm.input_id(@form, @field_name)}
        name={PhoenixForm.input_name(@form, @field_name)}
        type={@type}
        class={[
          "w-full phx-no-feedback:input phx-no-feedback:input-bordered",
          @errors == [] && "input input-bordered",
          @errors != [] && "input input-error placeholder-danger bg-red-50"
        ]}
        value={PhoenixForm.normalize_value(@type, @value)}
        {@rest}
      />
      <.error_tag form={@form} name={@field_name} field_options={@field_options} />
    </div>
    """
  end

  defp get_value(form, field) do
    changeset_value = Map.get(form.source.changes, field)

    case changeset_value do
      nil -> Map.get(form.data, field)
      value -> value
    end
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
  attr(:name, :string, required: true, doc: "name of the field the select should be for")
  attr(:field_options, :map, required: true, doc: "field options for the corresponding field")
  attr(:form, :any, required: true, doc: "form the select should be part of")
  attr(:selected, :list, required: true, doc: "the selected values")
  attr(:show_select_all, :boolean, required: true, doc: "whether to display the select all button")
  attr(:show_more, :boolean, required: true, doc: "whether there are more options to show")
  attr(:search_event, :string, default: "search", doc: "the event that will be sent when the search input changes")

  def multi_select(assigns) do
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
      <Backpex.HTML.Form.error_tag form={@form} name={@name} field_options={@field_options} />
      <div tabindex="0" class="dropdown-content z-[1] menu bg-base-100 rounded-box w-full overflow-y-auto shadow">
        <div class="max-h-72 p-2">
          <%= PhoenixForm.search_input(
            @form,
            :"#{@name}_search",
            placeholder: Backpex.translate("Search"),
            value: @search_input,
            phx_change: @search_event,
            phx_target: @event_target,
            class: "input input-sm input-bordered mb-2 w-full"
          ) %>

          <p :if={@options == []} class="w-full">
            <%= @not_found_text %>
          </p>

          <button
            :if={Enum.any?(@options)}
            type="button"
            class="text-primary my-2 text-sm underline hover:cursor-pointer"
            phx-click="toggle-select-all"
            phx-value-field-name={@name}
            phx-target={@event_target}
          >
            <%= if @show_select_all do %>
              <%= Backpex.translate("Select all") %>
            <% else %>
              <%= Backpex.translate("Deselect all") %>
            <% end %>
          </button>

          <%= PhoenixForm.hidden_input(@form, @name,
            name: PhoenixForm.input_name(@form, @name),
            value: ""
          ) %>
          <div class="my-2 w-full">
            <div
              :for={{label, value} <- @options}
              class="mt-2 flex space-x-2"
              phx-click="toggle-option"
              phx-value-id={value}
              phx-target={@event_target}
            >
              <%= PhoenixForm.checkbox(
                @form,
                @name,
                class: "checkbox checkbox-sm checkbox-primary",
                checked: selected?(value, @selected),
                name: PhoenixForm.input_name(@form, @name) <> "[]",
                checked_value: value,
                value: value,
                hidden_input: false
              ) %>
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

  defp selected?(id, selected), do: Enum.any?(selected, fn {_label, value} -> id == value end)

  @doc """
  Generates form field input errors.
  """
  @doc type: :component
  attr(:form, :any, required: true, doc: "form the error tag should be for")
  attr(:name, :atom, required: true, doc: "the name of the field")
  attr(:field_options, :map, required: true, doc: "the field options")

  def error_tag(assigns) do
    assigns =
      assigns
      |> assign(:translated_errors, translated_form_errors(assigns.form, assigns.name, assigns.field_options))

    ~H"""
    <div
      :for={translated_error <- @translated_errors}
      class="invalid-feedback mt-1 text-xs italic text-red-500"
      phx-feedback-for={PhoenixForm.input_name(@form, @name)}
    >
      <%= translated_error %>
    </div>
    """
  end

  def form_errors?(false, _changeset), do: false

  def form_errors?(true = _show_errors, changeset) do
    Ecto.Changeset.traverse_errors(changeset, & &1)
    |> Enum.count() > 0
  end

  defp translated_form_errors(form, name, field_options) do
    Keyword.get_values(form.errors || [], name)
    |> Enum.reduce([], fn el, acc ->
      el = translate_error(el, field_options)

      Keyword.merge(acc, [el])
    end)
    |> Enum.map(&Backpex.translate(&1, :error))
  end

  defp translate_error(error, %{translate_error: translate_error} = _field_options), do: translate_error.(error)
  defp translate_error(error, _field_options), do: error
end
