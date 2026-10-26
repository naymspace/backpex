defmodule Backpex.Test.AddressLive do
  use Backpex.LiveResource,
    adapter_config: [
      schema: Backpex.Test.Address,
      repo: Backpex.Test.Repo,
      update_changeset: &Backpex.Test.Address.update_changeset/3,
      create_changeset: &Backpex.Test.Address.create_changeset/3
    ],
    fluid?: true,
    persist: [:order, :filters, :columns, :metrics]

  @impl Backpex.LiveResource
  def layout(_assigns), do: {Backpex.Test.Layouts, :admin}

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
        options: %{
          "Europe" => [Germany: "de", Austria: "at", Switzerland: "ch"],
          "North America" => [USA: "us", Canada: "ca"]
        }
      }
    ]
  end
end
