defmodule Backpex.Test.CategoryLive do
  use Backpex.LiveResource,
    adapter_config: [
      schema: Backpex.Test.Category,
      repo: Backpex.Test.Repo,
      update_changeset: &Backpex.Test.Category.update_changeset/3,
      create_changeset: &Backpex.Test.Category.create_changeset/3
    ],
    init_order: %{by: :name, direction: :asc},
    persist: [:order, :filters, :columns, :metrics]

  @impl Backpex.LiveResource
  def layout(_assigns), do: {Backpex.Test.Layouts, :admin}

  @impl Backpex.LiveResource
  def singular_name, do: "Category"

  @impl Backpex.LiveResource
  def plural_name, do: "Categories"

  @impl Backpex.LiveResource
  def fields do
    [
      name: %{
        module: Backpex.Fields.Text,
        label: "Name",
        searchable: true
      }
    ]
  end
end
