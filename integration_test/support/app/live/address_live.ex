defmodule Backpex.Test.AddressLive do
  @moduledoc """
  Addresses with UUID primary keys and the default `init_order`. They are the children of the HasManyThrough field of
  `Backpex.Test.UserLive`.
  """
  use Backpex.LiveResource,
    adapter_config: [
      schema: Backpex.Test.Address,
      repo: Backpex.Test.Repo,
      update_changeset: &Backpex.Test.Address.changeset/3,
      create_changeset: &Backpex.Test.Address.changeset/3
    ]

  @impl Backpex.LiveResource
  def layout(_assigns), do: {Backpex.Test.Layouts, :admin}

  @impl Backpex.LiveResource
  def singular_name, do: "Address"

  @impl Backpex.LiveResource
  def plural_name, do: "Addresses"

  @impl Backpex.LiveResource
  def fields do
    [
      street: %{module: Backpex.Fields.Text, label: "Street Name"},
      zip: %{module: Backpex.Fields.Text, label: "Zip Code"},
      city: %{module: Backpex.Fields.Text, label: "City"},
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
