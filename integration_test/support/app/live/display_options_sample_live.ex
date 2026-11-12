defmodule Backpex.Test.DisplayOptionsSampleLive do
  @moduledoc """
  Samples whose fields set the display options every field shares: `align` and `index_column_class` (text and number,
  as a string and as a function), `render` (email), `help_text` and `align_label` (text and email, as a value and as a
  function) and `translate_error` (number). The url field sets none of them and shows the defaults.
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
      text: %{
        module: Backpex.Fields.Text,
        label: "Text",
        align: :right,
        index_column_class: "text-column",
        help_text: "Shown below the text input",
        align_label: :bottom
      },
      number: %{
        module: Backpex.Fields.Number,
        label: "Number",
        align: :center,
        index_column_class: fn assigns -> "number-column-#{assigns.live_action}" end,
        translate_error: &translate_number_error/1
      },
      email: %{
        module: Backpex.Fields.Email,
        label: "Email",
        render: &render_email/1,
        help_text: fn assigns -> "Help text of the #{assigns.live_action} form" end,
        align_label: fn assigns -> if assigns.live_action == :edit, do: :top, else: :bottom end
      },
      url: %{module: Backpex.Fields.URL, label: "URL"}
    ]
  end

  defp translate_number_error({"is invalid", opts}), do: {"must be a whole number", opts}
  defp translate_number_error(error), do: error

  defp render_email(assigns) do
    ~H"""
    <a class="rendered-email" href={"mailto:#{@value}"}>Write to {@value}</a>
    """
  end
end
