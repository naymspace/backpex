defmodule DemoWeb.CategoryLive do
  use Backpex.LiveResource,
    adapter_config: [
      schema: Demo.Category,
      repo: Demo.Repo,
      update_changeset: &Demo.Category.update_changeset/3,
      create_changeset: &Demo.Category.create_changeset/3
    ],
    layout: {DemoWeb.Layouts, :admin},
    pubsub: [
      name: Demo.PubSub,
      topic: "categories",
      event_prefix: "category_"
    ],
    init_order: %{by: :name, direction: :asc}

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
