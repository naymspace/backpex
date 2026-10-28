defmodule Backpex.Integration.Options.FieldDisplayOptionsTest do
  @moduledoc """
  Checks the display options every field shares (`align`, `index_column_class`, `render`, `help_text`, `align_label` and
  `translate_error`) in the views, through `Backpex.Test.DisplayOptionsSampleLive`. Its url field sets none of them and
  shows the defaults. The help texts and label alignments of every field module are checked in
  `Backpex.Fields.FormInputOptionsTest`.
  """
  use Backpex.ConnCase, async: true

  setup do
    %{sample: insert(:sample, text: "Sample text", number: 7, email: "mail@example.com", url: "https://example.com")}
  end

  describe "align and index_column_class" do
    test "are applied to the header and the cells of the index column", %{conn: conn} do
      conn
      |> visit(~p"/admin/display-options-samples")
      |> assert_has("thead th > div.justify-end.text-right.text-column", text: "Text")
      |> assert_has("tbody td > div.justify-end.text-right.text-column", text: "Sample text")
      |> assert_has("thead th > div.justify-center.text-center.number-column-index", text: "Number")
      |> assert_has("tbody td > div.justify-center.text-center.number-column-index", text: "7")
    end

    test "default to a left aligned column without extra classes", %{conn: conn} do
      conn
      |> visit(~p"/admin/display-options-samples")
      |> assert_has("thead th > div[class='text-xs font-medium flex justify-start text-left']", text: "URL")
      |> assert_has("tbody td > div[class='flex justify-start text-left']", text: "https://example.com")
    end
  end

  describe "render" do
    test "renders the value on the index view", %{conn: conn} do
      conn
      |> visit(~p"/admin/display-options-samples")
      |> assert_has("td a.rendered-email[href='mailto:mail@example.com']", text: "Write to mail@example.com")
    end

    test "renders the value on the show view", %{conn: conn, sample: sample} do
      conn
      |> visit(~p"/admin/display-options-samples/#{sample.id}/show")
      |> assert_has("dd a.rendered-email[href='mailto:mail@example.com']", text: "Write to mail@example.com")
      |> assert_has("dd", text: "https://example.com")
      |> refute_has("a.rendered-email", text: "https://example.com")
    end
  end

  describe "help_text" do
    test "renders a string or the result of a function below the input", %{conn: conn, sample: sample} do
      conn
      |> visit(~p"/admin/display-options-samples/new")
      |> assert_has(help_text("text"), text: "Shown below the text input", exact: true)
      |> assert_has(help_text("email"), text: "Help text of the new form", exact: true)
      |> refute_has(help_text("url"))

      conn
      |> visit(~p"/admin/display-options-samples/#{sample.id}/edit")
      |> assert_has(help_text("email"), text: "Help text of the edit form", exact: true)
    end
  end

  describe "align_label" do
    test "aligns the label to a value or the result of a function", %{conn: conn, sample: sample} do
      conn
      |> visit(~p"/admin/display-options-samples/new")
      |> assert_has(label_container("text", "sm:self-end"))
      |> assert_has(label_container("email", "sm:self-end"))
      |> assert_has(label_container("url", "sm:self-center"))

      conn
      |> visit(~p"/admin/display-options-samples/#{sample.id}/edit")
      |> assert_has(label_container("email", "sm:self-start"))
    end
  end

  describe "translate_error" do
    test "translates the errors of the field", %{conn: conn} do
      conn
      |> visit(~p"/admin/display-options-samples/new")
      |> fill_in("Number", with: "abc")
      |> assert_has(error("number"), text: "must be a whole number", exact: true)
      |> refute_has(error("number"), text: "is invalid")
    end

    test "leaves the errors untranslated without the option", %{conn: conn} do
      conn
      |> visit(~p"/admin/samples/new")
      |> fill_in("Number", with: "abc")
      |> assert_has(error("number"), text: "is invalid", exact: true)
    end
  end

  defp help_text(name), do: "div.fieldset:has(input[name='change[#{name}]']) > p.text-base-content\\/60"

  defp error(name), do: "div.fieldset:has(input[name='change[#{name}]']) > p.text-error"

  defp label_container(name, align_class) do
    "dl:has(input[name='change[#{name}]']) > dt.#{String.replace(align_class, ":", "\\:")}"
  end
end
