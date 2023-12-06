defmodule DemoWeb.ProductLive do
  use Backpex.LiveResource,
    layout: {DemoWeb.Layouts, :admin},
    schema: Demo.Product,
    repo: Demo.Repo,
    update_changeset: &Demo.Product.changeset/2,
    create_changeset: &Demo.Product.changeset/2,
    pubsub: Demo.PubSub,
    topic: "products",
    event_prefix: "product_"

  @impl Backpex.LiveResource
  def singular_name, do: "Product"

  @impl Backpex.LiveResource
  def plural_name, do: "Products"

  @impl Backpex.LiveResource
  def filters do
    [
      quantity: %{
        module: DemoWeb.Filters.ProductQuantityRange
      }
    ]
  end

  @impl Backpex.LiveResource
  def fields do
    [
      name: %{
        module: Backpex.Fields.Text,
        label: "Name",
        searchable: true
      },
      manufacturer: %{
        module: Backpex.Fields.URL,
        label: "Manufacturer URL",
        orderable: false
      },
      quantity: %{
        module: Backpex.Fields.Number,
        label: "Quantity",
        align: :center,
        translate_error: fn
          {_msg, [type: :integer, validation: :cast] = metadata} ->
            {"has to be a number", metadata}

          error ->
            error
        end
      },
      price: %{
        module: Backpex.Fields.Currency,
        label: "Price",
        align: :right
      },
      suppliers: %{
        module: Backpex.Fields.InlineCRUD,
        label: "Suppliers",
        type: :assoc,
        except: [:index],
        child_fields: [
          name: %{
            module: Backpex.Fields.Text,
            label: "Name"
          },
          url: %{
            module: Backpex.Fields.Text,
            label: "URL"
          }
        ]
      }
    ]
  end

  @impl Backpex.LiveResource
  def metrics do
    [
      total_quantity: %{
        module: Backpex.Metrics.Value,
        label: "In Stock",
        class: "w-1/3",
        select: dynamic([i], sum(i.quantity)),
        format: fn value ->
          Integer.to_string(value) <> " Products"
        end
      }
    ]
  end
end
