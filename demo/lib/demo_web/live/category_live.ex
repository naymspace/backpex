defmodule DemoWeb.CategoryLive do
  use Backpex.LiveResource,
    layout: {DemoWeb.Layouts, :admin},
    schema: Demo.Category,
    repo: Demo.Repo,
    update_changeset: &Demo.Category.update_changeset/3,
    create_changeset: &Demo.Category.create_changeset/3,
    pubsub: Demo.PubSub,
    topic: "categories",
    event_prefix: "category_"

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
