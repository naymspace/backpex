defmodule DemoWeb.CategoryLive do
  use Backpex.LiveResource,
    adapter_config: [
      schema: Demo.Category,
      repo: Demo.Repo,
      update_changeset: &Demo.Category.update_changeset/3,
      create_changeset: &Demo.Category.create_changeset/3
    ],
    init_order: %{by: :name, direction: :asc},
    persist: [:order, :filters, :columns, :metrics]

  import Ecto.Query, warn: false

  alias Demo.Post
  alias Demo.Repo

  @impl Backpex.LiveResource
  def layout(_assigns), do: {DemoWeb.Layouts, :admin}

  @impl Backpex.LiveResource
  def singular_name, do: "Category"

  @impl Backpex.LiveResource
  def plural_name, do: "Categories"

  @impl Backpex.LiveResource
  def on_item_deleting(_socket, category) do
    posts = from(post in Post, where: post.category_id == ^category.id)

    if Repo.exists?(posts) do
      {:error, "#{category.name} can't be deleted, because posts belong to it."}
    else
      :ok
    end
  end

  @impl Backpex.LiveResource
  def fields do
    [
      name: %{
        module: Backpex.Fields.Text,
        label: "Name",
        searchable: true
      }
    ]
  end
end
