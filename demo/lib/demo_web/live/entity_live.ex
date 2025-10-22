defmodule DemoWeb.EntityLive do
  use Backpex.LiveResource,
    adapter_config: [
      schema: Demo.Entity,
      repo: Demo.Repo,
      update_changeset: &Demo.Entity.changeset/3,
      create_changeset: &Demo.Entity.changeset/3
    ],
    layout: {DemoWeb.Layouts, :admin},
    fluid?: true

  @impl Backpex.LiveResource
  def singular_name, do: "Entity"

  @impl Backpex.LiveResource
  def plural_name, do: "Entities"

  @impl Backpex.LiveResource
  def item_actions(default_actions) do
    default_actions
    |> Keyword.delete(:delete)
  end

  @impl Backpex.LiveResource
  def can?(_assigns, :index, _item), do: true

  @impl Backpex.LiveResource
  def can?(_assigns, _action, _item), do: false

  @impl Backpex.LiveResource
  def fields do
    [
      identity: %{
        module: Backpex.Fields.Text,
        label: "Identity",
        searchable: true
      },
      type: %{
        module: Backpex.Fields.Text,
        label: "Type",
        searchable: true,
        readonly: true
      },
      fields: %{
        module: Backpex.Fields.Textarea,
        rows: 10,
        label: "Fields",
        searchable: true,
        readonly: true,
        except: [:index]
      }
    ]
  end
end
