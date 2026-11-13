# quokka:skip-module-directive-reordering
defmodule Backpex.Fields.Select do
  @config_schema [
    options: [
      doc: "List of possibly grouped options or function that receives the assigns.",
      type: {:or, [{:list, :any}, {:map, :any, :any}, {:fun, 1}]},
      required: true
    ],
    prompt: [
      doc: "The text to be displayed when no option is selected or function that receives the assigns.",
      type: {:or, [:string, {:fun, 1}]}
    ],
    searchable_options: [
      doc: "Whether the select has a search input that filters the options.",
      type: :boolean,
      default: false
    ],
    debounce: [
      doc: "Timeout value (in milliseconds), \"blur\" or function that receives the assigns.",
      type: {:or, [:pos_integer, :string, {:fun, 1}]}
    ],
    throttle: [
      doc: "Timeout value (in milliseconds) or function that receives the assigns.",
      type: {:or, [:pos_integer, {:fun, 1}]}
    ]
  ]

  @moduledoc """
  A field for handling a select value.

  The form and the index form render a `Backpex.HTML.Combobox.combobox/1`. The `prompt` is shown while no option is
  selected, and a field with a `prompt` has a button that clears the selection. Without a `prompt` the select has no
  empty state, like a native select: it selects its first option while the item has no value.

  ## Field-specific options

  See `Backpex.Field` for general field options.

  #{NimbleOptions.docs(@config_schema)}

  ## Example

      @impl Backpex.LiveResource
      def fields do
        [
          role: %{
            module: Backpex.Fields.Select,
            label: "Role",
            options: [Admin: admin, User: user]
          }
        ]
      end
  """
  use Backpex.Field, config_schema: @config_schema

  alias Backpex.HTML.Combobox

  @impl Backpex.Field
  def render_value(assigns) do
    options = get_options(assigns)
    label = get_label(assigns.value, options)

    assigns = assign(assigns, :label, label)

    ~H"""
    <p class={@live_action in [:index, :resource_action] && "truncate"}>
      {HTML.pretty_value(@label)}
    </p>
    """
  end

  @impl Backpex.Field
  def render_form(assigns) do
    options = get_options(assigns)

    assigns =
      assigns
      |> assign(:options, options)
      |> assign(:label_id, "#{assigns.form[assigns.name].id}-label")
      |> assign_prompt(assigns.field_options)

    ~H"""
    <div>
      <Layout.field_container>
        <:label :if={not @hide_label} align={Backpex.Field.align_label(@field_options, assigns)}>
          <Layout.input_label id={@label_id} for={"#{@form[@name].id}-trigger"} text={@field_options[:label]} />
        </:label>
        <Combobox.combobox
          field={@form[@name]}
          value={selected_value(@form[@name].value, @options, @prompt)}
          options={@options}
          placeholder={@prompt}
          clearable={@prompt != nil}
          searchable={@field_options[:searchable_options] == true}
          readonly={@readonly}
          translate_error_fun={Backpex.Field.translate_error_fun(@field_options, assigns)}
          help_text={Backpex.Field.help_text(@field_options, assigns)}
          live_resource={@live_resource}
          phx-debounce={Backpex.Field.debounce(@field_options, assigns)}
          phx-throttle={Backpex.Field.throttle(@field_options, assigns)}
          {Backpex.Field.label_attrs(assigns, @label_id)}
        />
      </Layout.field_container>
    </div>
    """
  end

  @impl Backpex.Field
  def render_index_form(assigns) do
    options = get_options(assigns)

    assigns =
      assigns
      |> assign(:options, options)
      |> Backpex.Field.assign_index_form()
      |> assign_prompt(assigns.field_options)

    ~H"""
    <div>
      <BackpexForm.index_form form={@form} name={@name} item={@item} live_resource={@live_resource} class="relative">
        <Combobox.combobox
          id={"index-form-input-#{@name}-#{LiveResource.primary_value(@item, @live_resource)}"}
          field={@form[:value]}
          value={selected_value(@form[:value].value, @options, @prompt)}
          options={@options}
          placeholder={@prompt}
          clearable={@prompt != nil}
          searchable={@field_options[:searchable_options] == true}
          size="sm"
          input_class={[
            "input min-w-32 h-auto min-h-(--size) w-full py-1",
            @valid && "not-hover:input-ghost",
            !@valid && "input-error bg-error/10"
          ]}
          disabled={@readonly}
          hide_errors
          live_resource={@live_resource}
          aria-label={@field_options[:label]}
        />
      </BackpexForm.index_form>
    </div>
    """
  end

  @impl Backpex.Field
  def index_editable_change({name, _field_options}, value, _assigns), do: %{name => value}

  # Like a native select, a select without a prompt has no empty state: without a value it selects its first option.
  defp selected_value(value, options, nil = _prompt) when value in [nil, ""] do
    case flatten_options(options) do
      [{_label, first} | _options] -> first
      [] -> value
    end
  end

  defp selected_value(value, _options, _prompt), do: value

  defp get_label(value, options) do
    options
    |> flatten_options()
    |> Enum.find_value(value, fn {label, option_value} ->
      if to_string(option_value) == to_string(value), do: label
    end)
  end

  # Normalizes all option shapes supported by `Phoenix.HTML.Form.options_for_select/2`
  # into a flat list of `{label, value}` tuples.
  defp flatten_options(options) do
    Enum.flat_map(options, fn
      {:hr, nil} -> []
      {_group_label, group} when is_list(group) or (is_map(group) and not is_struct(group)) -> flatten_options(group)
      {label, value} -> [{label, value}]
      option when is_list(option) -> [{Keyword.fetch!(option, :key), Keyword.fetch!(option, :value)}]
      :hr -> []
      option -> [{option, option}]
    end)
  end

  defp assign_prompt(assigns, field_options) do
    prompt =
      case Map.get(field_options, :prompt) do
        nil -> nil
        prompt when is_function(prompt) -> prompt.(assigns)
        prompt -> prompt
      end

    assign(assigns, :prompt, prompt)
  end

  defp get_options(assigns) do
    case Map.get(assigns.field_options, :options) do
      options when is_function(options) -> options.(assigns)
      options -> options
    end
  end
end
