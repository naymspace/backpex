defmodule DemoWeb.FilmReviewLive do
  use Backpex.LiveResource,
    adapter_config: [
      schema: Demo.FilmReview,
      repo: Demo.Repo,
      update_changeset: &Demo.FilmReview.update_changeset/3,
      create_changeset: &Demo.FilmReview.create_changeset/3
    ],
    layout: {DemoWeb.Layouts, :admin},
    full_text_search: :generated_tsvector

  @impl Backpex.LiveResource
  def singular_name, do: "Film Review"

  @impl Backpex.LiveResource
  def plural_name, do: "Film Reviews"

  @impl Backpex.LiveResource
  def render_resource_slot(assigns, :index, :before_page_title) do
    ~H"""
    <Backpex.HTML.Layout.alert kind={:info} closable={false}>
      This resource uses the full-text search functionality. The search accepts web search query operators. For example,
      a dash (-) excludes words.
    </Backpex.HTML.Layout.alert>
    """
  end

  @impl Backpex.LiveResource
  def can?(_assigns, :delete, _item), do: false

  @impl Backpex.LiveResource
  def can?(_assigns, _action, _item), do: true

  @impl Backpex.LiveResource
  def item_actions(default_actions) do
    Keyword.delete(default_actions, :delete)
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
