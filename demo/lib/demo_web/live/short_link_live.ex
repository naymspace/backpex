defmodule DemoWeb.ShortLinkLive do
  use DemoWeb, :verified_routes

  use Backpex.LiveResource,
    adapter_config: [
      schema: Demo.ShortLink,
      repo: Demo.Repo,
      update_changeset: &Demo.ShortLink.changeset/3,
      create_changeset: &Demo.ShortLink.changeset/3
    ],
    primary_key: :short_key,
    layout: {DemoWeb.Layouts, :admin}

  @impl Backpex.LiveResource
  def singular_name, do: "Short Link"

  @impl Backpex.LiveResource
  def plural_name, do: "Short Links"

  # short links might be saved by a user and should always keep working
  @impl Backpex.LiveResource
  def can?(_assigns, :delete, _item), do: false
  def can?(_assigns, _action, _item), do: true

  def return_to(_socket, _assigns, :edit, _item) do
    # since the primary key might be updated, we go to the index page
    ~p"/admin/short-links"
  end

  @impl Backpex.LiveResource
  def fields do
    [
      short_key: %{
        module: Backpex.Fields.Text,
        label: "URL Suffix"
      },
      url: %{
        module: Backpex.Fields.URL,
        label: "URL",
        placeholder: "https://example.com"
      },
      product: %{
        module: Backpex.Fields.BelongsTo,
        label: "Product",
        display_field: :name,
        prompt: "Choose product..."
      }
    ]
  end
end
