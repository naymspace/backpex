defmodule Backpex.Test.PostLive do
  @moduledoc """
  Posts, the LiveResource with the most options: a filter of every kind with defaults and presets, value metrics,
  `persist`, a `context_assigns` list, the "Save & Continue editing" button and a custom form action, an index editable
  BelongsTo field with an `options_query`, a HasMany field and a field with a `visible` function.
  """
  use Backpex.LiveResource,
    adapter_config: [
      schema: Backpex.Test.Post,
      repo: Backpex.Test.Repo,
      update_changeset: &Backpex.Test.Post.update_changeset/3,
      create_changeset: &Backpex.Test.Post.create_changeset/3
    ],
    save_and_continue_button?: true,
    persist: [:order, :filters, :columns],
    context_assigns: []

  import Ecto.Query, warn: false

  alias Backpex.LiveResource
  alias Backpex.Metrics.Value
  alias Backpex.Router
  alias Backpex.Test.CategoryLive
  alias Backpex.Test.Filters.DateTimeRange
  alias Backpex.Test.Filters.PostCategorySelect
  alias Backpex.Test.Filters.PostLikeRange
  alias Backpex.Test.Filters.PostPublished
  alias Backpex.Test.Filters.PostUserMultiSelect
  alias Backpex.Test.Layouts
  alias Backpex.Test.TagLive
  alias Backpex.Test.UserLive

  @impl LiveResource
  def layout(_assigns), do: {Layouts, :admin}

  @impl LiveResource
  def singular_name, do: "Post"

  @impl LiveResource
  def plural_name, do: "Posts"

  @impl LiveResource
  def filters do
    [
      category_id: %{module: PostCategorySelect, label: "Category"},
      user_id: %{module: PostUserMultiSelect, label: "Users"},
      likes: %{
        module: PostLikeRange,
        label: "Likes",
        presets: [
          %{label: "Over 100", values: fn -> %{"start" => 100, "end" => nil} end},
          %{label: "1-99", values: fn -> %{"start" => 1, "end" => 99} end}
        ]
      },
      inserted_at: %{module: DateTimeRange, label: "Created at"},
      published: %{module: PostPublished, label: "Published?", default: ["published"]}
    ]
  end

  @impl LiveResource
  def fields do
    [
      title: %{module: Backpex.Fields.Text, label: "Title", searchable: true},
      body: %{module: Backpex.Fields.Textarea, label: "Body", except: [:index]},
      published: %{module: Backpex.Fields.Boolean, label: "Published"},
      likes: %{
        module: Backpex.Fields.Number,
        label: "Likes",
        visible: fn assigns -> assigns.live_action not in [:new, :edit] end
      },
      user: %{
        module: Backpex.Fields.BelongsTo,
        label: "Author",
        display_field: :full_name,
        select: dynamic([user: u], fragment("concat(?, ' ', ?)", u.first_name, u.last_name)),
        options_query: fn query, _assigns ->
          query
          |> where([user], is_nil(user.deleted_at))
          |> select_merge([user], %{
            full_name: fragment("concat(?, ' ', ?)", user.first_name, user.last_name)
          })
        end,
        index_editable: true,
        live_resource: UserLive
      },
      category: %{
        module: Backpex.Fields.BelongsTo,
        label: "Category",
        display_field: :name,
        live_resource: CategoryLive
      },
      tags: %{
        module: Backpex.Fields.HasMany,
        label: "Tags",
        orderable: false,
        display_field: :name,
        live_resource: TagLive
      }
    ]
  end

  # Editing an existing post offers a third button that saves and opens the post.
  @impl LiveResource
  def form_actions(%{live_action: :edit}, default_actions) do
    [{:show, %{label: "Save & Show", soft: true}} | default_actions]
  end

  def form_actions(_assigns, default_actions), do: default_actions

  @impl LiveResource
  def return_to(socket, assigns, :edit, :show, item) do
    Router.get_path(socket, assigns.live_resource, assigns.params, :show, item)
  end

  @impl LiveResource
  def metrics do
    [
      total_likes: %{
        module: Value,
        label: "Total likes",
        select: dynamic([p], sum(p.likes)),
        format: fn value -> Integer.to_string(value) <> " likes" end
      },
      published_posts: %{
        module: Value,
        label: "Published Posts",
        select: dynamic([p], count(fragment("CASE WHEN ? = TRUE THEN 1 ELSE NULL END", p.published))),
        format: &Integer.to_string/1
      },
      all_posts: %{
        module: Value,
        label: "All posts",
        aggregate: :count,
        ignore_filters: [:published],
        format: &Integer.to_string/1
      }
    ]
  end
end
