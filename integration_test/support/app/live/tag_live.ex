defmodule Backpex.Test.TagLive do
  @moduledoc """
  Tags with UUID primary keys, the target of the HasMany field of `Backpex.Test.PostLive`. They have
  `init_order: %{by: :name, direction: :desc}`, the default pagination and the item action
  `Backpex.Test.ItemActions.DuplicateTag`, which has fields.
  """
  use Backpex.LiveResource,
    adapter_config: [
      schema: Backpex.Test.Tag,
      repo: Backpex.Test.Repo,
      update_changeset: &Backpex.Test.Tag.changeset/3,
      create_changeset: &Backpex.Test.Tag.changeset/3
    ],
    init_order: %{by: :name, direction: :desc}

  @impl Backpex.LiveResource
  def layout(_assigns), do: {Backpex.Test.Layouts, :admin}

  @impl Backpex.LiveResource
  def singular_name, do: "Tag"

  @impl Backpex.LiveResource
  def plural_name, do: "Tags"

  @impl Backpex.LiveResource
  def fields do
    [
      name: %{module: Backpex.Fields.Text, label: "Name", searchable: true}
    ]
  end

  @impl Backpex.LiveResource
  def item_actions(default_actions) do
    [duplicate: %{module: Backpex.Test.ItemActions.DuplicateTag, only: [:row, :show]}] ++ default_actions
  end
end
