defmodule DemoWeb.CarLive do
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


    @moduledoc """
    This module is similar to  `PersonLive` in that it demos the use of a InlineCRUD set for type `:map`.
    It also demos how you can use the power of `Backpex` to do a poor man's polymorphism by using `Backpex.LiveResource`
    to control the values entered into the generic `:map` field while  reusing the same schema
    for different entity types.

    It also is an example of how you could validate the values in the `:map` field by using a `validate`
    function and calling `Backpex.Fields.InlineCRUD.changeset` inside the `changeset` function.
    """

  import Ecto.Query, only: [where: 3]

  @impl Backpex.LiveResource
  def singular_name, do: "Car"

  @impl Backpex.LiveResource
  def plural_name, do: "Cars"


  #
  # Added the item_query function to filter entities by type
  #
  def item_query(query, _, _assigns) do
    query
    |> where([entity], entity.type=="car")
  end


  #
  # Added the changeset function to create a new entity with type "car",
  # and validate the child fields in the entity
  #
  def changeset(entity, params, metadata \\ []) do
    entity
    |> Demo.Entity.changeset(params |> Map.put("type", "car"))
    |> Backpex.Fields.InlineCRUD.changeset(:fields, metadata)
  end

  @impl Backpex.LiveResource
  def fields do
    [
      identity: %{
        module: Backpex.Fields.Text,
        label: "Model",
        searchable: true
      },
      fields: %{
        module: Backpex.Fields.InlineCRUD,
        label: "Information",
        type: :map,
        except: [:index],
        child_fields: [
          engine_size: %{
            module: Backpex.Fields.Text,
            label: "Engine Size (cc)",
            input_type: :integer
          },
          colour: %{
            module: Backpex.Fields.Text,
            label: "Colour"
          },
          year: %{
            module: Backpex.Fields.Text,
            label: "Year",
            input_type: :integer

          }
        ],
        validate: fn changeset->
          changeset
          |> Ecto.Changeset.validate_required([:colour, :year])
          |> Ecto.Changeset.validate_number(:year, greater_than: 1900, less_than: Date.utc_today().year, message: "must be between 1900 and #{Date.utc_today().year}")
        end
      },
    ]
  end
end
