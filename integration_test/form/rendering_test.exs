defmodule Backpex.Integration.Form.RenderingTest do
  use Backpex.ConnCase, async: true

  test "groups fields in the panels of panels/0", %{conn: conn} do
    conn
    |> visit(~p"/admin/users/new")
    |> assert_has("div", text: "Names")
  end

  test "renders association fields as inputs", %{conn: conn} do
    insert(:user)
    insert(:category)
    insert(:tag)

    conn
    |> visit(~p"/admin/posts/new")
    # The label of a combobox opens it through its trigger; the anchor input holds the value of the form field.
    |> assert_has("label[for=resource-form_user_id-trigger]", text: "Author")
    |> assert_has("#resource-form_user_id input[data-part=anchor][name='change[user_id]']")
    |> assert_has("label[for=resource-form_category_id-trigger]", text: "Category")
    |> assert_has("#resource-form_category_id input[data-part=anchor][name='change[category_id]']")
    |> assert_has("label[for=resource-form_tags-trigger]", text: "Tags")
    |> assert_has("#resource-form_tags[data-multiple] input[data-part=anchor][name='change[tags]']")
  end

  test "hides a field whose visible function returns false", %{conn: conn} do
    conn
    |> visit(~p"/admin/posts/new")
    |> assert_has("input[name='change[title]']")
    |> refute_has("input[name='change[likes]']")
  end

  test "derives the input ids from the id of the form", %{conn: conn} do
    conn
    |> visit(~p"/admin/posts/new")
    |> assert_has("input#resource-form_title[name='change[title]']")
  end
end
