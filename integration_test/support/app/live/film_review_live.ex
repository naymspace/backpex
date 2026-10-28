defmodule Backpex.Test.FilmReviewLive do
  @moduledoc """
  Film reviews with a `full_text_search` column and a `before_page_title` resource slot.
  """
  use Backpex.LiveResource,
    adapter_config: [
      schema: Backpex.Test.FilmReview,
      repo: Backpex.Test.Repo,
      update_changeset: &Backpex.Test.FilmReview.changeset/3,
      create_changeset: &Backpex.Test.FilmReview.changeset/3
    ],
    full_text_search: :generated_tsvector

  @impl Backpex.LiveResource
  def layout(_assigns), do: {Backpex.Test.Layouts, :admin}

  @impl Backpex.LiveResource
  def singular_name, do: "Film Review"

  @impl Backpex.LiveResource
  def plural_name, do: "Film Reviews"

  @impl Backpex.LiveResource
  def render_resource_slot(assigns, :index, :before_page_title) do
    ~H"""
    <Backpex.HTML.Layout.alert kind={:info} closable={false}>
      This resource uses the full-text search functionality.
    </Backpex.HTML.Layout.alert>
    """
  end

  @impl Backpex.LiveResource
  def fields do
    [
      title: %{module: Backpex.Fields.Text, label: "Title"},
      overview: %{module: Backpex.Fields.Textarea, label: "Overview"}
    ]
  end
end
