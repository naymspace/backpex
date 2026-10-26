defmodule Backpex.Test.InvoiceLive do
  @moduledoc """
  Invoices, an index-only resource: `can?/3` only allows `:index` and the router only routes `only: [:index]`.
  """
  use Backpex.LiveResource,
    adapter_config: [
      schema: Backpex.Test.Invoice,
      repo: Backpex.Test.Repo
    ]

  @impl Backpex.LiveResource
  def layout(_assigns), do: {Backpex.Test.Layouts, :admin}

  @impl Backpex.LiveResource
  def singular_name, do: "Invoice"

  @impl Backpex.LiveResource
  def plural_name, do: "Invoices"

  @impl Backpex.LiveResource
  def can?(_assigns, :index, _item), do: true
  def can?(_assigns, _action, _item), do: false

  # `can?/3` alone would keep the bulk delete button, disabled.
  @impl Backpex.LiveResource
  def item_actions(default_actions), do: Keyword.delete(default_actions, :delete)

  @impl Backpex.LiveResource
  def fields do
    [
      company: %{module: Backpex.Fields.Text, label: "Company"},
      amount: %{module: Backpex.Fields.Currency, label: "Amount"}
    ]
  end
end
