defmodule DemoWeb.InvoiceLive do
  use Backpex.LiveResource,
    adapter_config: [
      schema: Demo.Invoice,
      repo: Demo.Repo
    ]

  alias Backpex.Fields.Currency
  alias Backpex.Fields.Text

  @impl Backpex.LiveResource
  def layout(_assigns), do: {DemoWeb.Layouts, :admin}

  @impl Backpex.LiveResource
  def singular_name, do: "Invoice"

  @impl Backpex.LiveResource
  def plural_name, do: "Invoices"

  @impl Backpex.LiveResource
  def can?(_assigns, :index, _item), do: true

  @impl Backpex.LiveResource
  def can?(_assigns, _action, _item), do: false

  @impl Backpex.LiveResource
  def item_actions(default_actions) do
    default_actions
    |> Keyword.delete(:delete)
  end

  @impl Backpex.LiveResource
  def fields do
    [
      company: %{
        module: Text,
        label: "Company"
      },
      amount: %{
        module: Currency,
        label: "Amount"
      }
    ]
  end
end
