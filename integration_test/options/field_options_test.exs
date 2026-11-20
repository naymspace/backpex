defmodule Backpex.Integration.Options.FieldOptionsTest do
  @moduledoc """
  Checks the `default`, `can?` and `render_form` options every field shares, through the fields of
  `Backpex.Test.FieldOptionsSampleLive`.
  """
  use Backpex.ConnCase, async: true

  import Phoenix.LiveViewTest, only: [form: 2, put_submitter: 2, render_submit: 2]

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
      |> assert_has("input[data-part=anchor][name='change[category_id]'][value='#{category.id}']")
      |> assert_has("#resource-form_category_id [role=option][data-value='#{category.id}'][aria-selected=true]")
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

    test "saves no value a crafted client sends for the field on the new form", %{conn: conn} do
      conn
      |> visit(~p"/admin/field-options-samples/new")
      |> save(%{text: "New", email: "forged@example.com"})

      assert %Sample{email: nil} = Repo.get_by!(Sample, text: "New")
    end

    # The boolean field has a `can?` that is false on the edit view.
    test "saves no value a crafted client sends for the field on the edit form", %{conn: conn, sample: sample} do
      conn
      |> visit(~p"/admin/field-options-samples/#{sample.id}/edit")
      |> refute_has("input[name='change[boolean]']")
      |> save(%{text: "After", boolean: "true"})

      assert %Sample{text: "After", boolean: false} = Repo.get!(Sample, sample.id)
    end
  end

  describe "only" do
    # The url field has `only: [:index, :show]`.
    test "saves no value a crafted client sends for the field on the edit form", %{conn: conn} do
      sample = insert(:sample, text: "Before", url: "https://example.com")

      conn
      |> visit(~p"/admin/field-options-samples/#{sample.id}/edit")
      |> refute_has("input[name='change[url]']")
      |> save(%{text: "After", url: "https://forged.example.com"})

      assert %Sample{text: "After", url: "https://example.com"} = Repo.get!(Sample, sample.id)
    end
  end

  describe "except" do
    # The date field has `except: [:new, :edit]`.
    test "saves no value a crafted client sends for the field on the edit form", %{conn: conn} do
      sample = insert(:sample, text: "Before", date: ~D[2024-01-01])

      conn
      |> visit(~p"/admin/field-options-samples/#{sample.id}/edit")
      |> refute_has("input[name='change[date]']")
      |> save(%{text: "After", date: "2030-12-31"})

      assert %Sample{text: "After", date: ~D[2024-01-01]} = Repo.get!(Sample, sample.id)
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

  # A crafted client can send params for any field, not only for the inputs of the form.
  defp save(session, params) do
    unwrap(session, fn view ->
      view
      |> form("#resource-form")
      |> put_submitter("button[value=save]")
      |> render_submit(%{change: params})
    end)
  end
end
