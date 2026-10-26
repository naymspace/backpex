defmodule Backpex.Test.InvoiceLive do
  use Backpex.LiveResource,
    adapter_config: [
      schema: Backpex.Test.Invoice,
      repo: Backpex.Test.Repo
    ],
    persist: [:order, :filters, :columns, :metrics]

  @impl Backpex.LiveResource
  def layout(_assigns), do: {Backpex.Test.Layouts, :admin}

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
        module: Backpex.Fields.Text,
        label: "Company"
      },
      amount: %{
        module: Backpex.Fields.Currency,
        label: "Amount"
      }
    ]
  end
end
