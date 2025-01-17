defmodule DemoWeb.AddressLive do
  use Backpex.LiveResource,
    adapter_config: [
      schema: Demo.Address,
      repo: Demo.Repo,
      update_changeset: &Demo.Address.update_changeset/3,
      create_changeset: &Demo.Address.create_changeset/3
    ],
    layout: {DemoWeb.Layouts, :admin},
    pubsub: [
      name: Demo.PubSub,
      topic: "addresses",
      event_prefix: "address_"
    ],
    fluid?: true

  @impl Backpex.LiveResource
  def singular_name, do: "Address"

  @impl Backpex.LiveResource
  def plural_name, do: "Addresses"

  @impl Backpex.LiveResource
  def fields do
    [
      street: %{
        module: Backpex.Fields.Text,
        label: "Street Name",
        searchable: true
      },
      zip: %{
        module: Backpex.Fields.Text,
        label: "Zip Code",
        searchable: true
      },
      city: %{
        module: Backpex.Fields.Text,
        label: "City",
        searchable: true
      },
      country: %{
        module: Backpex.Fields.Select,
        label: "Country",
        options: [Germany: "de", Austria: "at", Switzerland: "ch"]
      }
    ]
  end
end
