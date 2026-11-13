defmodule Backpex.Test.IndexEditSampleLive do
  @moduledoc """
  Samples with one index editable field of every field type that implements `c:Backpex.Field.render_index_form/1`, so
  every inline edit form of the index view is rendered and saved in a test.
  """
  use Backpex.LiveResource,
    adapter_config: [
      schema: Backpex.Test.Sample,
      repo: Backpex.Test.Repo,
      update_changeset: &Backpex.Test.Sample.changeset/3,
      create_changeset: &Backpex.Test.Sample.changeset/3
    ]

  @impl Backpex.LiveResource
  def layout(_assigns), do: {Backpex.Test.Layouts, :admin}

  @impl Backpex.LiveResource
  def singular_name, do: "Sample"

  @impl Backpex.LiveResource
  def plural_name, do: "Samples"

  @impl Backpex.LiveResource
  def fields do
    [
      text: %{module: Backpex.Fields.Text, label: "Text", index_editable: true},
      number: %{module: Backpex.Fields.Number, label: "Number", index_editable: true},
      boolean: %{module: Backpex.Fields.Boolean, label: "Boolean", index_editable: true},
      select: %{
        module: Backpex.Fields.Select,
        label: "Select",
        options: [One: "one", Two: "two", Three: "three"],
        prompt: "Choose one",
        index_editable: true
      },
      date: %{module: Backpex.Fields.Date, label: "Date", index_editable: true},
      date_time: %{module: Backpex.Fields.DateTime, label: "Date Time", index_editable: true},
      time: %{module: Backpex.Fields.Time, label: "Time", index_editable: true},
      email: %{module: Backpex.Fields.Email, label: "Email", index_editable: true},
      category: %{
        module: Backpex.Fields.BelongsTo,
        label: "Category",
        display_field: :name,
        live_resource: Backpex.Test.CategoryLive,
        prompt: "Choose a category",
        index_editable: true
      }
    ]
  end
end
