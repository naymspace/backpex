defmodule DemoWeb.CategoryLive do
  use Backpex.LiveResource,
    adapter_config: [
      schema: Demo.Category,
      repo: Demo.Repo,
      update_changeset: &Demo.Category.update_changeset/3,
      create_changeset: &Demo.Category.create_changeset/3
    ],
    init_order: %{by: :name, direction: :asc}

  alias Backpex.Fields.Text

  @impl Backpex.LiveResource
  def layout(_assigns), do: {DemoWeb.Layouts, :admin}

  @impl Backpex.LiveResource
  def singular_name, do: "Category"

  @impl Backpex.LiveResource
  def plural_name, do: "Categories"

  @impl Backpex.LiveResource
  def fields do
    [
      name: %{
        module: Text,
        label: "Name",
        searchable: true
      }
    ]
  end
end
