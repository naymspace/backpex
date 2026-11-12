defmodule Backpex.Test.NoteLive do
  @moduledoc "A minimal LiveResource with an integer primary key."
  use Backpex.LiveResource,
    adapter_config: [
      schema: Backpex.Test.Note,
      repo: Backpex.Test.Repo,
      update_changeset: &Backpex.Test.Note.changeset/3,
      create_changeset: &Backpex.Test.Note.changeset/3
    ]

  @impl Backpex.LiveResource
  def layout(_assigns), do: {Backpex.Test.Layouts, :admin}

  @impl Backpex.LiveResource
  def singular_name, do: "Note"

  @impl Backpex.LiveResource
  def plural_name, do: "Notes"

  @impl Backpex.LiveResource
  def fields do
    [
      title: %{module: Backpex.Fields.Text, label: "Title", searchable: true}
    ]
  end
end
