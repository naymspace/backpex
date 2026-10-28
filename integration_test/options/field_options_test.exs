defmodule Backpex.Integration.Options.FieldOptionsTest do
  @moduledoc """
  Checks the `default`, `can?` and `render_form` options every field shares, through the fields of
  `Backpex.Test.FieldOptionsSampleLive`.
  """
  use Backpex.ConnCase, async: true

  alias Backpex.Test.Sample

  describe "default" do
    setup do
      %{category: insert(:category, name: "Default Category")}
    end

    test "prefills the new form", %{conn: conn, category: category} do
      conn
      |> visit(~p"/admin/field-options-samples/new")
      |> assert_has("input[name='change[text]'][value='Prefilled text']")
      |> assert_has("input[name='change[number]'][value='42']")
      |> assert_has("select[name='change[category_id]'] option[value='#{category.id}'][selected]")
    end

    test "is saved with the new item", %{conn: conn, category: category} do
      conn
      |> visit(~p"/admin/field-options-samples/new")
      |> click_button("Save")
      |> assert_path(~p"/admin/field-options-samples")

      assert [%Sample{text: "Prefilled text", number: 42, category_id: category_id}] = Repo.all(Sample)
      assert category_id == category.id
    end

    test "does not replace the values of an existing item on the edit form", %{conn: conn} do
      sample = insert(:sample, text: "Existing text", number: nil, category: nil)

      conn
      |> visit(~p"/admin/field-options-samples/#{sample.id}/edit")
      |> assert_has("input[name='change[text]'][value='Existing text']")
      |> refute_has("input[name='change[number]'][value='42']")
      |> refute_has("select[name='change[category_id]'] option[selected][value]")
    end
  end

  describe "can?" do
    # The email field has `can?: fn assigns -> assigns.live_action in [:show, :edit] end`.
    setup do
      %{sample: insert(:sample, text: "Sample", email: "visible@example.com")}
    end

    test "hides the field on the index view", %{conn: conn} do
      conn
      |> visit(~p"/admin/field-options-samples")
      |> assert_has("thead th", text: "Text")
      |> refute_has("thead th", text: "Email")
      |> refute_has("td", text: "visible@example.com")
    end

    test "hides the field on the new form", %{conn: conn} do
      conn
      |> visit(~p"/admin/field-options-samples/new")
      |> assert_has("input[name='change[text]']")
      |> refute_has("input[name='change[email]']")
    end

    test "shows the field on the show view", %{conn: conn, sample: sample} do
      conn
      |> visit(~p"/admin/field-options-samples/#{sample.id}/show")
      |> assert_has("dt", text: "Email")
      |> assert_has("dd", text: "visible@example.com")
    end

    test "shows the field on the edit form", %{conn: conn, sample: sample} do
      conn
      |> visit(~p"/admin/field-options-samples/#{sample.id}/edit")
      |> assert_has("input[name='change[email]'][value='visible@example.com']")
    end
  end

  describe "render_form" do
    test "renders the form field with the given function", %{conn: conn} do
      conn
      |> visit(~p"/admin/field-options-samples/new")
      |> assert_has("#custom-textarea-form input#custom-textarea[name='change[textarea]']")
      |> refute_has("textarea[name='change[textarea]']")
    end

    test "submits the value of the custom form field", %{conn: conn} do
      sample = insert(:sample, text: "Sample", textarea: "Old text")

      conn
      |> visit(~p"/admin/field-options-samples/#{sample.id}/edit")
      |> assert_has("input#custom-textarea[value='Old text']")
      |> fill_in("Custom textarea", with: "New text")
      |> click_button("Save")
      |> assert_path(~p"/admin/field-options-samples")

      assert Repo.get!(Sample, sample.id).textarea == "New text"
    end
  end
end
