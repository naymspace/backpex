defmodule Backpex.Test.ProductShortLinksLive do
  @moduledoc """
  A LiveResource of products whose relation fields point to `Backpex.Test.ShortLink`, a schema with the string primary
  key `short_key` and no `id` column: an index editable `Backpex.Fields.BelongsTo` (`featured_short_link`) and a
  `Backpex.Fields.HasMany` (`short_links`). A short link that is deselected in the has many field is deleted
  (`on_replace: :delete`). Products are created with `Backpex.Test.ProductLive`, so there is no `:new` view.
  """
  use Backpex.LiveResource,
    adapter_config: [
      schema: Backpex.Test.Product,
      repo: Backpex.Test.Repo,
      update_changeset: &Backpex.Test.Product.relations_changeset/3,
      create_changeset: &Backpex.Test.Product.relations_changeset/3
    ]

  alias Backpex.Test.ShortLinkLive

  @impl Backpex.LiveResource
  def layout(_assigns), do: {Backpex.Test.Layouts, :admin}

  @impl Backpex.LiveResource
  def singular_name, do: "Product"

  @impl Backpex.LiveResource
  def plural_name, do: "Products"

  @impl Backpex.LiveResource
  def can?(_assigns, :new, _item), do: false
  def can?(_assigns, _action, _item), do: true

  @impl Backpex.LiveResource
  def fields do
    [
      name: %{module: Backpex.Fields.Text, label: "Name"},
      featured_short_link: %{
        module: Backpex.Fields.BelongsTo,
        label: "Featured Short Link",
        display_field: :url,
        live_resource: ShortLinkLive,
        prompt: "No short link",
        index_editable: true
      },
      short_links: %{
        module: Backpex.Fields.HasMany,
        label: "Short Links",
        display_field: :url,
        live_resource: ShortLinkLive
      }
    ]
  end
end
