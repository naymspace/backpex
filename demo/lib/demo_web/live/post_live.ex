defmodule DemoWeb.PostLive do
  use Backpex.LiveResource,
    adapter_config: [
      schema: Demo.Post,
      repo: Demo.Repo,
      update_changeset: &Demo.Post.update_changeset/3,
      create_changeset: &Demo.Post.create_changeset/3
    ],
    layout: {DemoWeb.Layouts, :admin},
    fluid?: true,
    save_and_continue_button?: true

  import Ecto.Query, warn: false

  @impl Backpex.LiveResource
  def singular_name, do: "Post"

  @impl Backpex.LiveResource
  def plural_name, do: "Posts"

  @impl Backpex.LiveResource
  def filters do
    [
      category_id: %{
        module: DemoWeb.Filters.PostCategorySelect,
        label: "Category"
      },
      user_id: %{
        module: DemoWeb.Filters.PostUserMultiSelect,
        label: "Users"
      },
      likes: %{
        module: DemoWeb.Filters.PostLikeRange,
        label: "Likes",
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
        label: "Created at",
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
        label: "Published?",
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
        rows: 10,
        except: [:index],
        align_label: :center
      },
      published: %{
        module: Backpex.Fields.Boolean,
        label: "Published",
        align: :center,
        index_editable: true
      },
      show_likes: %{
        module: Backpex.Fields.Boolean,
        label: "Show likes",
        select: dynamic([post: p], fragment("? > 0", p.likes)),
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
        searchable: true,
        render: fn assigns ->
          ~H"""
          <p>{Number.Delimit.number_to_delimited(@value, precision: 0, delimiter: ".")}</p>
          """
        end
      },
      user: %{
        module: Backpex.Fields.BelongsTo,
        label: "Author",
        prompt: "Please select an author",
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
        searchable: true,
        live_resource: DemoWeb.UserLive
      },
      category: %{
        module: Backpex.Fields.BelongsTo,
        label: "Category",
        display_field: :name,
        searchable: true,
        live_resource: DemoWeb.CategoryLive,
        custom_alias: :custom_category
      },
      tags: %{
        module: Backpex.Fields.HasMany,
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
        class: "lg:w-1/4",
        select: dynamic([p], sum(p.likes)),
        format: fn value ->
          Integer.to_string(value) <> " likes"
        end
      },
      published_posts: %{
        module: Backpex.Metrics.Value,
        label: "Published Posts",
        class: "lg:w-1/4",
        select: dynamic([p], count(fragment("CASE WHEN ? = TRUE THEN 1 ELSE NULL END", p.published))),
        format: fn value ->
          Integer.to_string(value)
        end
      }
    ]
  end
end
