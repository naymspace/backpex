defmodule DemoWeb.ShortLinkLive do
  use Backpex.LiveResource,
    layout: {DemoWeb.Layouts, :admin},
    schema: Demo.ShortLink,
    repo: Demo.Repo,
    update_changeset: &Demo.ShortLink.changeset/3,
    create_changeset: &Demo.ShortLink.changeset/3,
    pubsub: Demo.PubSub,
    topic: "short_links",
    event_prefix: "short_link_"

  @impl Backpex.LiveResource
  def singular_name, do: "Short Link"

  @impl Backpex.LiveResource
  def plural_name, do: "Short Links"

  # short links might be saved by a user and should always keep working
  @impl Backpex.LiveResource
  def can?(_assigns, :delete, _item), do: false
  def can?(_assigns, _action, _item), do: true

  @impl Backpex.LiveResource
  def fields do
    [
      short_key: %{
        module: Backpex.Fields.Text,
        label: "URL Suffix",
      },
      url: %{
        module: Backpex.Fields.URL,
        label: "URL",
        placeholder: "https://example.com",
      },
      product: %{
        module: Backpex.Fields.BelongsTo,
        label: "Product",
        source: Demo.Product,
        display_field: :name,
      }
    ]
  end
end
