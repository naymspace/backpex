defmodule DemoWeb.CategoryLive do
  use Backpex.LiveResource,
    adapter: Backpex.Adapters.Ash,
    adapter_config: [
      resource: Demo.Blog.Category
    ],
    layout: {DemoWeb.Layouts, :admin},
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
