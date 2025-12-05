defmodule DemoWeb.Live.Category.EditItemActionLiveTest do
  use DemoWeb.ConnCase, async: false

  import Demo.EctoFactory
  import Phoenix.LiveViewTest

  describe "edit item action on index view" do
    test "redirects to index view", %{conn: conn} do
      category = insert(:category, name: "Tech")

      conn
      |> visit(~p"/admin/categories")
      |> assert_has("td", text: category.name, exact: true)
      |> unwrap(fn view ->
        view
        |> element("button[aria-label='Edit'][phx-value-item-id='#{category.id}']")
        |> render_click()
      end)
      |> assert_path("/admin/categories/#{category.id}/edit")
      |> unwrap(fn view ->
        view
        |> form("#resource-form", change: %{name: "Updated Tech"})
        |> put_submitter("button[value=save]")
        |> render_submit()
      end)
      |> assert_path("/admin/categories")
      |> assert_has("td", text: "Updated Tech", exact: true)
    end

    test "redirects to index view on cancel", %{conn: conn} do
      category = insert(:category, name: "Tech")

      conn
      |> visit(~p"/admin/categories")
      |> assert_has("td", text: category.name, exact: true)
      |> unwrap(fn view ->
        view
        |> element("button[aria-label='Edit'][phx-value-item-id='#{category.id}']")
        |> render_click()
      end)
      |> assert_path("/admin/categories/#{category.id}/edit")
      |> unwrap(fn view ->
        view
        |> element("a:has(button[value='cancel'])")
        |> render_click()
      end)
      |> assert_path("/admin/categories")
      |> assert_has("td", text: category.name, exact: true)
    end
  end

  describe "edit item action on show view" do
    test "redirects to show view", %{conn: conn} do
      category = insert(:category, name: "Tech")

      conn
      |> visit(~p"/admin/categories/#{category.id}/show")
      |> assert_has("dd", text: category.name, exact: true)
      |> assert_has("#item-action-edit")
      |> unwrap(fn view ->
        view
        |> element("#item-action-edit")
        |> render_click()
      end)
      |> assert_path("/admin/categories/#{category.id}/edit")
      |> unwrap(fn view ->
        view
        |> form("#resource-form", change: %{name: "Updated Tech"})
        |> put_submitter("button[value=save]")
        |> render_submit()
      end)
      |> assert_path("/admin/categories/#{category.id}/show")
      |> assert_has("dd", text: "Updated Tech", exact: true)
    end

    test "redirects to show view on cancel", %{conn: conn} do
      category = insert(:category, name: "Tech")

      conn
      |> visit(~p"/admin/categories/#{category.id}/show")
      |> assert_has("dd", text: category.name, exact: true)
      |> assert_has("#item-action-edit")
      |> unwrap(fn view ->
        view
        |> element("#item-action-edit")
        |> render_click()
      end)
      |> assert_path("/admin/categories/#{category.id}/edit")
      |> unwrap(fn view ->
        view
        |> element("a:has(button[value='cancel'])")
        |> render_click()
      end)
      |> assert_path("/admin/categories/#{category.id}/show")
      |> assert_has("dd", text: category.name, exact: true)
    end
  end
end
