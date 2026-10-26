defmodule Backpex.Test.ShortLinkLive do
  use Phoenix.VerifiedRoutes, endpoint: Backpex.Test.Endpoint, router: Backpex.Test.Router

  use Backpex.LiveResource,
    adapter_config: [
      schema: Backpex.Test.ShortLink,
      repo: Backpex.Test.Repo,
      update_changeset: &Backpex.Test.ShortLink.changeset/3,
      create_changeset: &Backpex.Test.ShortLink.changeset/3
    ],
    primary_key: :short_key,
    persist: [:order, :filters, :columns, :metrics]

  @impl Backpex.LiveResource
  def layout(_assigns), do: {Backpex.Test.Layouts, :admin}

  @impl Backpex.LiveResource
  def singular_name, do: "Short Link"

  @impl Backpex.LiveResource
  def plural_name, do: "Short Links"

  # short links might be saved by a user and should always keep working
  @impl Backpex.LiveResource
  def can?(_assigns, :delete, _item), do: false
  def can?(_assigns, _action, _item), do: true

  @impl Backpex.LiveResource
  def return_to(_socket, _assigns, :edit, _form_action, _item) do
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
