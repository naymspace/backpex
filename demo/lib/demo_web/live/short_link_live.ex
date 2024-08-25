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

  @impl Backpex.LiveResource
  def can?(_assigns, :index, _item), do: true

  @impl Backpex.LiveResource
  def can?(_assigns, _action, _item), do: true

  @impl Backpex.LiveResource
  def item_actions(default_actions) do
    default_actions
    |> Keyword.drop([:delete])
  end

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
