defmodule DemoWeb.FilmReviewLive do
  use Backpex.LiveResource,
    adapter_config: [
      schema: Demo.FilmReview,
      repo: Demo.Repo,
      update_changeset: &Demo.FilmReview.update_changeset/3,
      create_changeset: &Demo.FilmReview.create_changeset/3
    ],
    layout: {DemoWeb.Layouts, :admin},
    pubsub: Demo.PubSub,
    topic: "film_reviews",
    event_prefix: "film_reviews_",
    full_text_search: :generated_tsvector

  @impl Backpex.LiveResource
  def singular_name, do: "Film Review"

  @impl Backpex.LiveResource
  def plural_name, do: "Film Reviews"

  @impl Backpex.LiveResource
  def render_resource_slot(assigns, :index, :before_page_title) do
    ~H"""
    <div role="alert" class="alert alert-info my-4 text-sm">
      <Backpex.HTML.CoreComponents.icon name="hero-information-circle" class="h-5 w-5" />
      <span>
        This resource uses the full-text search functionality. The search accepts web search query operators. For example, a dash (-) excludes words.
      </span>
    </div>
    """
  end

  @impl Backpex.LiveResource
  def can?(_assigns, :delete, _item), do: false

  @impl Backpex.LiveResource
  def can?(_assigns, _action, _item), do: true

  @impl Backpex.LiveResource
  def item_actions(default_actions) do
    default_actions
    |> Keyword.drop([:delete])
  end

  @impl Backpex.LiveResource
  def fields do
    [
      title: %{
        module: Backpex.Fields.Text,
        label: "Title"
      },
      overview: %{
        module: Backpex.Fields.Textarea,
        label: "Overview",
        index_column_class: "max-w-sm"
      }
    ]
  end
end
