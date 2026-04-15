defmodule DemoWeb.AddressLive do
  use Backpex.LiveResource,
    adapter_config: [
      schema: Demo.Address,
      repo: Demo.Repo,
      update_changeset: &Demo.Address.update_changeset/3,
      create_changeset: &Demo.Address.create_changeset/3
    ],
    fluid?: true

  alias Backpex.Fields.Select
  alias Backpex.Fields.Text

  @impl Backpex.LiveResource
  def layout(_assigns), do: {DemoWeb.Layouts, :admin}

  @impl Backpex.LiveResource
  def singular_name, do: "Address"

  @impl Backpex.LiveResource
  def plural_name, do: "Addresses"

  @impl Backpex.LiveResource
  def fields do
    [
      street: %{
        module: Text,
        label: "Street Name",
        searchable: true
      },
      zip: %{
        module: Text,
        label: "Zip Code",
        searchable: true
      },
      city: %{
        module: Text,
        label: "City",
        searchable: true
      },
      country: %{
        module: Select,
        label: "Country",
        options: %{
          "Europe" => [Germany: "de", Austria: "at", Switzerland: "ch"],
          "North America" => [USA: "us", Canada: "ca"]
        }
      }
    ]
  end
end
