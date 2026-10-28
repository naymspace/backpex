defmodule Backpex.Test.FieldOptionsSampleLive do
  @moduledoc """
  Samples whose fields use the options every field shares: `default` (text, number and the category, which is looked up
  by the name "Default Category"), `can?` (email, only on the show and edit views) and `render_form` (textarea).
  """
  use Backpex.LiveResource,
    adapter_config: [
      schema: Backpex.Test.Sample,
      repo: Backpex.Test.Repo,
      update_changeset: &Backpex.Test.Sample.changeset/3,
      create_changeset: &Backpex.Test.Sample.changeset/3
    ]

  import Ecto.Query, only: [from: 2]

  @impl Backpex.LiveResource
  def layout(_assigns), do: {Backpex.Test.Layouts, :admin}

  @impl Backpex.LiveResource
  def singular_name, do: "Sample"

  @impl Backpex.LiveResource
  def plural_name, do: "Samples"

  @impl Backpex.LiveResource
  def fields do
    [
      text: %{module: Backpex.Fields.Text, label: "Text", default: fn _assigns -> "Prefilled text" end},
      number: %{module: Backpex.Fields.Number, label: "Number", default: fn _assigns -> 42 end},
      category: %{
        module: Backpex.Fields.BelongsTo,
        label: "Category",
        display_field: :name,
        live_resource: Backpex.Test.CategoryLive,
        prompt: "Choose a category",
        default: &default_category_id/1
      },
      email: %{
        module: Backpex.Fields.Email,
        label: "Email",
        can?: fn assigns -> assigns.live_action in [:show, :edit] end
      },
      textarea: %{module: Backpex.Fields.Textarea, label: "Textarea", render_form: &render_custom_textarea/1}
    ]
  end

  defp default_category_id(_assigns) do
    query = from c in Backpex.Test.Category, where: c.name == "Default Category", select: c.id
    Backpex.Test.Repo.one(query)
  end

  defp render_custom_textarea(assigns) do
    ~H"""
    <div id="custom-textarea-form">
      <label for="custom-textarea">Custom textarea</label>
      <input type="text" id="custom-textarea" name={@form[@name].name} value={@form[@name].value} />
    </div>
    """
  end
end
