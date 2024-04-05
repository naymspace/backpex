defmodule Backpex.Fields.Currency do
  @moduledoc """
  A field for handling a currency value.

  ## Options

  * `:debounce` - Optional integer timeout value (in milliseconds), "blur" or function that receives the assignes.
  * `:throttle` - Optional integer timeout value (in milliseconds) or function that receives the assignes.

  ## Schema

  `Backpex.Ecto.Amount.Type` provides a type for Ecto to store a amount. The underlying data type should be an integer.
  For a full list of configuration options see: https://hexdocs.pm/money/Money.html#module-configuration

      schema "article" do
        field :price, Backpex.Ecto.Amount.Type
        ...
      end

      schema "article" do
        field :price, Backpex.Ecto.Amount.Type, currency: :EUR, opts: [separator: ".", delimiter: ","]
        ...
      end

  ## Example

      @impl Backpex.LiveResource
      def fields do
        [
          price: %{
            module: Backpex.Fields.Currency,
            label: "Price"
          }
        ]
      end
  """
  use BackpexWeb, :field

  import Ecto.Query

  alias Backpex.Ecto.Amount.Type

  @impl Backpex.Field
  def render_value(assigns) do
    assigns = assign(assigns, :casted_value, maybe_cast_value(assigns.name, assigns.schema, assigns.value))

    ~H"""
    <p class={@live_action in [:index, :resource_action] && "truncate"}>
      <%= @casted_value %>
    </p>
    """
  end

  @impl Backpex.Field
  def render_form(assigns) do
    assigns = assign(assigns, :casted_value, maybe_cast_form(PhoenixForm.input_value(assigns.form, assigns.name)))

    ~H"""
    <div>
      <Layout.field_container>
        <:label align={Backpex.Field.align_label(@field_options, assigns)}>
          <Layout.input_label text={@field_options[:label]} />
        </:label>
        <BackpexForm.field_input
          type="number"
          field={@form[@name]}
          field_options={@field_options}
          value={@casted_value}
          phx-debounce={Backpex.Field.debounce(@field_options, assigns)}
          phx-throttle={Backpex.Field.throttle(@field_options, assigns)}
          step=".01"
          min="0"
        />
      </Layout.field_container>
    </div>
    """
  end

  @impl Backpex.Field
  def search_condition(schema_name, field_name, search_string) do
    dynamic(
      [{^schema_name, schema_name}],
      ilike(fragment("CAST(? AS TEXT)", schema_name |> field(^field_name)), ^search_string)
    )
  end

  defp maybe_cast_value(field_name, schema, value) do
    type = schema.__schema__(:type, field_name) || schema.__schema__(:virtual_type, field_name)

    case type do
      {:parameterized, Backpex.Ecto.Amount.Type, opts} ->
        {:ok, money} = Type.cast(value, opts)

        Money.to_string(money, Keyword.get(opts, :opts, []))

      _type ->
        value
    end
  end

  defp maybe_cast_form(val) when is_binary(val), do: val
  defp maybe_cast_form(nil), do: Decimal.new("0.00")
  defp maybe_cast_form(%Money{} = value), do: Money.to_decimal(value)
end
