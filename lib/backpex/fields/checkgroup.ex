defmodule Backpex.Fields.Checkgroup do
  @config_schema [
    options: [
      doc: "List of options or function that receives the assigns.",
      type: {:or, [{:list, :any}, {:fun, 1}]},
      required: true
    ],
    readonly: [
      doc: "Sets the field to readonly. Also see the [panels](/guides/fields/readonly.md) guide.",
      type: {:or, [:boolean, {:fun, 1}]}
    ]
  ]

  @moduledoc """
  A field for handling multiple checkboxes with predefined options.

  This field stores selected values as an array.

  > #### Schema and migration defaults {: .warning}
  >
  > You **must** declare `default: []` on the `{:array, _}` schema field *and* set a matching
  > SQL default (`DEFAULT '{}'::text[]` in PostgreSQL). Otherwise unchecking every box will
  > persist `NULL` instead of an empty array. The reason is Ecto's `filter_empty_values/3`:
  > the hidden sentinel input submits the scalar `""`, which Ecto treats as empty and replaces
  > with the schema default.
  >
  >     # Ecto schema
  >     field :roles, {:array, :string}, default: []
  >
  >     # Migration
  >     alter table(:users) do
  >       modify :roles, {:array, :string}, default: []
  >     end

  ## Field-specific options

  See `Backpex.Field` for general field options.

  #{NimbleOptions.docs(@config_schema)}

  ## Example

      @impl Backpex.LiveResource
      def fields do
        [
          roles: %{
            module: Backpex.Fields.Checkgroup,
            label: "Roles",
            options: [{"Admin", "admin"}, {"User", "user"}, {"Editor", "editor"}]
          }
        ]
      end
  """
  use Backpex.Field, config_schema: @config_schema

  @impl Backpex.Field
  def render_value(assigns) do
    options = get_options(assigns)
    labels = get_labels(assigns.value, options)

    assigns = assign(assigns, :labels, labels)

    ~H"""
    <p class={@live_action in [:index, :resource_action] && "truncate"}>
      {if @labels == [], do: raw("&mdash;"), else: @labels |> Enum.map(&HTML.pretty_value/1) |> Enum.join(", ")}
    </p>
    """
  end

  @impl Backpex.Field
  def render_form(assigns) do
    options = get_options(assigns)

    assigns = assign(assigns, :options, options)

    ~H"""
    <div>
      <Layout.field_container>
        <:label :if={not @hide_label} align={Backpex.Field.align_label(@field_options, assigns)}>
          <Layout.input_label as="span" text={@field_options[:label]} />
        </:label>
        <BackpexForm.input
          type="checkgroup"
          field={@form[@name]}
          options={@options}
          translate_error_fun={Backpex.Field.translate_error_fun(@field_options, assigns)}
          help_text={Backpex.Field.help_text(@field_options, assigns)}
          readonly={@readonly}
        />
      </Layout.field_container>
    </div>
    """
  end

  defp get_labels(value, options) do
    values = List.wrap(value) |> Enum.map(&to_string/1)

    options
    |> Enum.filter(fn {_label, option_value} -> to_string(option_value) in values end)
    |> Enum.map(fn {label, _value} -> label end)
  end

  defp get_options(assigns) do
    case Map.get(assigns.field_options, :options) do
      options when is_function(options) -> options.(assigns)
      options -> options
    end
  end
end
