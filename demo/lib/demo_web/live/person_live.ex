defmodule DemoWeb.PersonLive do
  @moduledoc """
  This module just demos the use of a InlineCRUD set for type `:map`.
  It also demos how you can use the power of `Backpex` to do a poor man's polymorphism by using `Backpex.LiveResource`
  to control the values entered into the generic `:map` field while  reusing the same schema
  for different entity types.
  """
  use Backpex.LiveResource,
    adapter_config: [
      schema: Demo.Entity,
      repo: Demo.Repo,
      update_changeset: &__MODULE__.changeset/3,
      create_changeset: &__MODULE__.changeset/3,
      item_query: &__MODULE__.item_query/3
    ],
    layout: {DemoWeb.Layouts, :admin},
    fluid?: true

  import Ecto.Query, only: [where: 3]

  alias Demo.Entity

  @impl Backpex.LiveResource
  def singular_name, do: "Person"

  @impl Backpex.LiveResource
  def plural_name, do: "Persons"

  #
  # Added the item_query function to filter entities by type
  #
  def item_query(query, _view, _assigns) do
    query
    |> where([entity], entity.type == "person")
  end

  #
  # Added the changeset function to create a changeset for a person entity
  #
  def changeset(entity, params, _metadata \\ []) do
    entity
    |> Entity.changeset(params |> Map.put("type", "person"))
  end

  @impl Backpex.LiveResource
  def fields do
    [
      identity: %{
        module: Backpex.Fields.Text,
        label: "Name",
        searchable: true
      },
      fields: %{
        module: Backpex.Fields.InlineCRUD,
        label: "Information",
        type: :map,
        except: [:index],
        child_fields: [
          email: %{
            module: Backpex.Fields.Text,
            label: "Email"
          },
          phone: %{
            module: Backpex.Fields.Text,
            label: "Phone"
          },
          age: %{
            module: Backpex.Fields.Text,
            label: "Age"
          },
          weight: %{
            module: Backpex.Fields.Text,
            label: "Weight (kg)"
          }
        ]
      }
    ]
  end
end
