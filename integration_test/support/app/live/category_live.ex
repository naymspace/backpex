defmodule Backpex.Test.CategoryLive do
  @moduledoc """
  Categories, the target of the BelongsTo fields of `Backpex.Test.PostLive` and `Backpex.Test.SampleLive`.
  """
  use Backpex.LiveResource,
    adapter_config: [
      schema: Backpex.Test.Category,
      repo: Backpex.Test.Repo,
      update_changeset: &Backpex.Test.Category.changeset/3,
      create_changeset: &Backpex.Test.Category.changeset/3
    ]

  @impl Backpex.LiveResource
  def layout(_assigns), do: {Backpex.Test.Layouts, :admin}

  @impl Backpex.LiveResource
  def singular_name, do: "Category"

  @impl Backpex.LiveResource
  def plural_name, do: "Categories"

  @impl Backpex.LiveResource
  def fields do
    [
      name: %{module: Backpex.Fields.Text, label: "Name"}
    ]
  end
end
