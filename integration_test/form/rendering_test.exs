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
    |> assert_has("label", text: "Author")
    |> assert_has("select[name='change[user_id]']")
    |> assert_has("label", text: "Category")
    |> assert_has("select[name='change[category_id]']")
    # HasMany fields render their label as a span.
    |> assert_has("span", text: "Tags")
  end

  test "hides a field whose visible function returns false", %{conn: conn} do
    conn
    |> visit(~p"/admin/posts/new")
    |> assert_has("input[name='change[title]']")
    |> refute_has("input[name='change[likes]']")
  end
end
