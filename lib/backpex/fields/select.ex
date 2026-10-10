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

  ## Ordering and searching

  The index view orders and searches select fields by the labels of their options instead of the stored values, so
  the results match what the user sees. Values without an option are ordered and searched by the stored value.

  To translate the labels, pass a function as `options`. Backpex calls it with the assigns of the index view when
  ordering or searching, so the labels are translated into the locale of the current user:

      role: %{
        module: Backpex.Fields.Select,
        label: "Role",
        options: fn _assigns -> [{gettext("Admin"), "admin"}, {gettext("User"), "user"}] end
      }

  > #### Info {: .info}
  >
  > When ordering or searching, the `:item` of the assigns is `nil`, or the `base_schema` of a resource action while
  > one is open, instead of the item of a row. Do not read the fields of the item in the `options` function of a field
  > that is orderable or searchable.
  """
  use Backpex.Field, config_schema: @config_schema
  import Ecto.Query
  alias Backpex.Fields.OptionLabels

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
      |> assign_prompt(assigns.field_options)

    ~H"""
    <div>
      <Layout.field_container>
        <:label :if={not @hide_label} align={Backpex.Field.align_label(@field_options, assigns)}>
          <Layout.input_label for={@form[@name]} text={@field_options[:label]} />
        </:label>
        <BackpexForm.input
          type="select"
          field={@form[@name]}
          options={@options}
          prompt={@prompt}
          readonly={@readonly}
          disabled={@readonly}
          translate_error_fun={Backpex.Field.translate_error_fun(@field_options, assigns)}
          help_text={Backpex.Field.help_text(@field_options, assigns)}
          phx-debounce={Backpex.Field.debounce(@field_options, assigns)}
          phx-throttle={Backpex.Field.throttle(@field_options, assigns)}
          aria-labelledby={Map.get(assigns, :aria_labelledby)}
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
        <BackpexForm.input
          id={"index-form-input-#{@name}-#{LiveResource.primary_value(@item, @live_resource)}"}
          type="select"
          field={@form[:value]}
          options={@options}
          prompt={@prompt}
          input_class={[
            "select select-sm",
            @valid && "not-hover:select-ghost",
            !@valid &&
              "select-error text-error-content bg-error/10 [&.select::picker(select)]:bg-base-100 [&.select::picker(select)]:text-base-content"
          ]}
          disabled={@readonly}
          hide_errors
          aria-label={@field_options[:label]}
        />
      </BackpexForm.index_form>
    </div>
    """
  end

  @impl Backpex.Field
  def index_editable_change({name, _field_options}, value, _assigns), do: %{name => value}

  @impl Backpex.Field
  def search_condition(schema_name, field_name, search_string, field, assigns) do
    label = OptionLabels.label_expression(schema_name, field_name, OptionLabels.options(field, assigns))

    dynamic(ilike(^label, ^search_string))
  end

  @impl Backpex.Field
  def order_expression(schema_name, field_name, field, assigns) do
    OptionLabels.label_expression(schema_name, field_name, OptionLabels.options(field, assigns))
  end

  defp get_label(value, options) do
    option =
      options
      |> OptionLabels.flatten()
      |> Enum.find(fn {_label, option_value} -> value?(option_value, value) end)

    case option do
      nil -> value
      {label, _value} -> label
    end
  end

  defp value?(value, to_compare), do: to_string(value) == to_string(to_compare)

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
