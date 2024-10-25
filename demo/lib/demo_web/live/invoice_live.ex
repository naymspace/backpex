defmodule DemoWeb.InvoiceLive do
  use Backpex.LiveResource,
    adapter_config: [
      schema: Demo.Invoice,
      repo: Demo.Repo,
      update_changeset: &Demo.Invoice.update_changeset/3,
      create_changeset: &Demo.Invoice.create_changeset/3
    ],
    layout: {DemoWeb.Layouts, :admin},
    pubsub: [
      name: Demo.PubSub,
      topic: "invoices",
      event_prefix: "invoice_"
    ]

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
    |> Keyword.drop([:delete])
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
        label: "Amount",
        align: :right
      }
    ]
  end
end
