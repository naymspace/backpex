defmodule Backpex.Test.PagedNoteLive do
  @moduledoc "Notes with `per_page_options: [3, 6, 12]` and `per_page_default: 6` instead of the defaults."
  use Backpex.LiveResource,
    adapter_config: [
      schema: Backpex.Test.Note,
      repo: Backpex.Test.Repo,
      update_changeset: &Backpex.Test.Note.changeset/3,
      create_changeset: &Backpex.Test.Note.changeset/3
    ],
    per_page_options: [3, 6, 12],
    per_page_default: 6

  @impl Backpex.LiveResource
  def layout(_assigns), do: {Backpex.Test.Layouts, :admin}

  @impl Backpex.LiveResource
  def singular_name, do: "Note"

  @impl Backpex.LiveResource
  def plural_name, do: "Notes"

  @impl Backpex.LiveResource
  def fields do
    [
      title: %{module: Backpex.Fields.Text, label: "Title"}
    ]
  end
end
