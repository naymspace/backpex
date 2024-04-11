defmodule DemoWeb.PostLive do
  use Backpex.LiveResource,
    layout: {DemoWeb.Layouts, :admin},
    schema: Demo.Post,
    repo: Demo.Repo,
    update_changeset: &Demo.Post.update_changeset/3,
    create_changeset: &Demo.Post.create_changeset/3,
    pubsub: Demo.PubSub,
    topic: "posts",
    event_prefix: "post_",
    fluid?: true

  @impl Backpex.LiveResource
  def singular_name, do: "Post"

  @impl Backpex.LiveResource
  def plural_name, do: "Posts"

  @impl Backpex.LiveResource
  def filters do
    [
      category_id: %{
        module: DemoWeb.Filters.PostCategorySelect
      },
      user_id: %{
        module: DemoWeb.Filters.PostUserMultiSelect
      },
      likes: %{
        module: DemoWeb.Filters.PostLikeRange,
        presets: [
          %{
            label: "Over 100",
            values: fn -> %{"start" => 100, "end" => nil} end
          },
          %{
            label: "1-99",
            values: fn -> %{"start" => 1, "end" => 99} end
          }
        ]
      },
      inserted_at: %{
        module: DemoWeb.Filters.DateTimeRange,
        presets: [
          %{
            label: "Last 7 Days",
            values: fn ->
              %{
                "start" => Date.add(Date.utc_today(), -7),
                "end" => Date.utc_today()
              }
            end
          },
          %{
            label: "Last 14 Days",
            values: fn ->
              %{
                "start" => Date.add(Date.utc_today(), -14),
                "end" => Date.utc_today()
              }
            end
          },
          %{
            label: "Last 30 Days",
            values: fn ->
              %{
                "start" => Date.add(Date.utc_today(), -30),
                "end" => Date.utc_today()
              }
            end
          }
        ]
      },
      published: %{
        module: DemoWeb.Filters.PostPublished,
        default: ["published"],
        presets: [
          %{
            label: "Both",
            values: fn -> [:published, :not_published] end
          },
          %{
            label: "Only published",
            values: fn -> [:published] end
          },
          %{
            label: "Only not published",
            values: fn -> [:not_published] end
          }
        ]
      }
    ]
  end

  @impl Backpex.LiveResource
  def fields do
    [
      title: %{
        module: Backpex.Fields.Text,
        label: "Title",
        searchable: true
      },
      body: %{
        module: Backpex.Fields.Textarea,
        label: "Body",
        except: [:index]
      },
      published: %{
        module: Backpex.Fields.Boolean,
        label: "Published",
        align: :center
      },
      show_likes: %{
        module: Backpex.Fields.Boolean,
        label: "Show likes",
        select: dynamic([post: p], fragment("? > 0", p.likes)),
        align: :center,
        except: [:index, :show]
      },
      likes: %{
        module: Backpex.Fields.Number,
        label: "Likes",
        visible: fn
          %{live_action: :new} = assigns ->
            Map.get(assigns.changeset.changes, :show_likes)

          %{live_action: :edit} = assigns ->
            Map.get(
              assigns.changeset.changes,
              :show_likes,
              Map.get(assigns.item, :show_likes, false)
            )

          _assigns ->
            true
        end,
        searchable: true
      },
      user: %{
        module: Backpex.Fields.BelongsTo,
        label: "Author",
        prompt: "Please select an author",
        display_field: :full_name,
        select: dynamic([user: u], fragment("concat(?, ' ', ?)", u.first_name, u.last_name)),
        options_query: fn query, _assigns ->
          query
          |> select_merge([user], %{
            full_name: fragment("concat(?, ' ', ?)", user.first_name, user.last_name)
          })
        end,
        searchable: true,
        live_resource: DemoWeb.UserLive
      },
      category: %{
        module: Backpex.Fields.BelongsTo,
        label: "Category",
        display_field: :name,
        searchable: true,
        live_resource: DemoWeb.CategoryLive
      },
      tags: %{
        module: Backpex.Fields.ManyToMany,
        label: "Tags",
        orderable: false,
        display_field: :name,
        live_resource: DemoWeb.TagLive
      },
      inserted_at: %{
        module: Backpex.Fields.DateTime,
        label: "Created At",
        only: [:index, :show]
      }
    ]
  end

  @impl Backpex.LiveResource
  def metrics do
    [
      total_likes: %{
        module: Backpex.Metrics.Value,
        label: "Total likes",
        class: "w-1/3",
        select: dynamic([p], sum(p.likes)),
        format: fn value ->
          Integer.to_string(value) <> " likes"
        end
      }
    ]
  end
end
