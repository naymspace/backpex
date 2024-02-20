defmodule DemoWeb.TagLive do
  use Backpex.LiveResource,
    layout: {DemoWeb.Layouts, :admin},
    schema: Demo.Tag,
    repo: Demo.Repo,
    update_changeset: &Demo.Tag.update_changeset/3,
    create_changeset: &Demo.Tag.create_changeset/3,
    pubsub: Demo.PubSub,
    topic: "tags",
    event_prefix: "tag_"

  @impl Backpex.LiveResource
  def singular_name, do: "Tag"

  @impl Backpex.LiveResource
  def plural_name, do: "Tags"

  @impl Backpex.LiveResource
  def fields do
    [
      name: %{
        module: Backpex.Fields.Text,
        label: "Name",
        searchable: true,
        placeholder: "Tag name"
      }
    ]
  end
end
