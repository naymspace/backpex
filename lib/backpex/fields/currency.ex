defmodule Backpex.Fields.Currency do
  @config_schema [
    debounce: [
      doc: "Timeout value (in milliseconds), \"blur\" or function that receives the assigns.",
      type: {:or, [:pos_integer, :string, {:fun, 1}]}
    ],
    throttle: [
      doc: "Timeout value (in milliseconds) or function that receives the assigns.",
      type: {:or, [:pos_integer, {:fun, 1}]}
    ],
    unit: [
      doc: "Unit to display with the currency value, e.g. '€'.",
      type: :string,
      default: "€"
    ],
    unit_position: [
      doc: "Position of the unit relative to the value, either `:before` or `:after`.",
      type: {:in, [:before, :after]},
      default: :before
    ],
    radix: [
      doc:
        "Character used as the decimal separator, e.g. ',' or '.'. Make sure this value matches the one you've configured in your Money library.",
      type: :string,
      default: ","
    ],
    thousands_separator: [
      doc:
        "Character used as the thousands separator, e.g. '.' or ','. Make sure this value matches the one you've configured in your Money library.",
      type: :string,
      default: "."
    ]
  ]

  @moduledoc """
  A field for handling a currency value.

  ## Field-specific options

  See `Backpex.Field` for general field options.

  #{NimbleOptions.docs(@config_schema)}

  ## Schema

  Backpex expects you to use a Money library or a similar approach for handling currency values and dumping / casting them correctly in your database schema.

  Ensure that your schema field is set up to handle the currency type appropriately.

  For example, if you are using the [Money](https://hex.pm/packages/money) library, your schema might look like this:

      schema "article" do
        field :price, Money.Ecto.Amount.Type
        ...
      end

  ## Example

      @impl Backpex.LiveResource
      def fields do
        [
          price: %{
            module: Backpex.Fields.Currency,
            label: "Price",
            unit: "€",
            radix: ",",
            thousands_separator: "."
          }
        ]
      end
  """
  use Backpex.Field, config_schema: @config_schema

  import Ecto.Query

  @impl Backpex.Field
  def render_value(assigns) do
    ~H"""
    <p class={@live_action in [:index, :resource_action] && "truncate"}>
      {@value}
    </p>
    """
  end

  @impl Backpex.Field
  def render_form(assigns) do
    assigns = assign(assigns, :mask_pattern, build_mask_pattern(assigns.field_options))

    ~H"""
    <div>
      <Layout.field_container>
        <:label align={Backpex.Field.align_label(@field_options, assigns)}>
          <Layout.input_label text={@field_options[:label]} />
        </:label>
        <BackpexForm.masked_number_input
          type="text"
          field={@form[@name]}
          translate_error_fun={Backpex.Field.translate_error_fun(@field_options, assigns)}
          help_text={Backpex.Field.help_text(@field_options, assigns)}
          phx-debounce={Backpex.Field.debounce(@field_options, assigns)}
          phx-throttle={Backpex.Field.throttle(@field_options, assigns)}
          radix={@field_options[:radix]}
          mask_pattern={@mask_pattern}
          thousands_separator={@field_options[:thousands_separator]}
        />
      </Layout.field_container>
    </div>
    """
  end

  @impl Backpex.Field
  def search_condition(schema_name, field_name, search_string) do
    dynamic(
      [{^schema_name, schema_name}],
      ilike(fragment("CAST(? AS TEXT)", field(schema_name, ^field_name)), ^search_string)
    )
  end

  defp build_mask_pattern(%{unit_position: :before} = field_option), do: "#{field_option.unit} num"
  defp build_mask_pattern(%{unit_position: :after} = field_option), do: "num #{field_option.unit}"
end
