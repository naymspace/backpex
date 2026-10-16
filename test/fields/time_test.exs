defmodule Backpex.Fields.TimeTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Backpex.Fields.Time

  describe "render_form/1" do
    test "renders the label" do
      doc = render_time_form(hide_label: false)

      assert doc |> LazyHTML.query("dt") |> LazyHTML.text() =~ "Opening time"
    end

    test "does not render the label when hide_label is set" do
      # InlineCRUD renders child fields with `hide_label: true` and shows the labels once as column headers.
      doc = render_time_form(hide_label: true)

      assert doc |> LazyHTML.query("dt") |> Enum.empty?()
      refute LazyHTML.text(doc) =~ "Opening time"
      refute doc |> LazyHTML.query(~s(input[type="time"])) |> Enum.empty?()
    end
  end

  defp render_time_form(assigns) do
    assigns =
      Keyword.merge(
        [
          name: :opening_time,
          field_options: %{module: Time, label: "Opening time"},
          form: Phoenix.Component.to_form(%{}, as: :change),
          readonly: false,
          type: :form
        ],
        assigns
      )

    html = render_component(&Time.render_form/1, assigns)
    LazyHTML.from_fragment(html)
  end
end
