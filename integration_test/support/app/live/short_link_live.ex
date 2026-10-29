defmodule Backpex.Test.ShortLinkLive do
  @moduledoc """
  Short links with the string primary key `short_key` and no `id` column. `can?/3` denies `:delete`, while the default
  delete item action stays.
  """
  use Backpex.LiveResource,
    adapter_config: [
      schema: Backpex.Test.ShortLink,
      repo: Backpex.Test.Repo,
      update_changeset: &Backpex.Test.ShortLink.changeset/3,
      create_changeset: &Backpex.Test.ShortLink.changeset/3
    ],
    primary_key: :short_key

  @impl Backpex.LiveResource
  def layout(_assigns), do: {Backpex.Test.Layouts, :admin}

  @impl Backpex.LiveResource
  def singular_name, do: "Short Link"

  @impl Backpex.LiveResource
  def plural_name, do: "Short Links"

  @impl Backpex.LiveResource
  def can?(_assigns, :delete, _item), do: false
  def can?(_assigns, _action, _item), do: true

  @impl Backpex.LiveResource
  def fields do
    [
      short_key: %{module: Backpex.Fields.Text, label: "URL Suffix"},
      url: %{module: Backpex.Fields.URL, label: "URL", searchable: true}
    ]
  end
end
