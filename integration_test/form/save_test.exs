defmodule Backpex.Integration.Form.SaveTest do
  use Backpex.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Backpex.Test.Tag

  test "creates an item and returns to the index view", %{conn: conn} do
    conn
    |> visit(~p"/admin/tags/new")
    |> fill_in("Name", with: "Phoenix")
    |> click_button("Save")
    |> assert_path(~p"/admin/tags")
    |> assert_has("table tbody tr", count: 1)
    |> assert_has("p", text: "Phoenix", exact: true)
  end

  test "prefills the form with the item, updates it and returns to the index view", %{conn: conn} do
    tag = insert(:tag, name: "Elixir")

    conn
    |> visit(~p"/admin/tags/#{tag.id}/edit")
    |> assert_has("input", label: "Name", value: "Elixir")
    |> fill_in("Name", with: "Phoenix")
    |> click_button("Save")
    |> assert_path(~p"/admin/tags")
    |> assert_has("table tbody tr", count: 1)
    |> assert_has("p", text: "Phoenix", exact: true)
  end

  # A submit without a submitter, e.g. `form.requestSubmit()` in a hook, sends the values without `save-type`.
  describe "without a submitter" do
    test "creates an item with the submitted values", %{conn: conn} do
      conn
      |> visit(~p"/admin/tags/new")
      |> unwrap(fn view -> view |> form("#resource-form", change: %{name: "Phoenix"}) |> render_submit() end)
      |> assert_path(~p"/admin/tags")
      |> assert_has("p", text: "Phoenix", exact: true)

      assert [%Tag{name: "Phoenix"}] = Repo.all(Tag)
    end

    test "updates the item with the submitted values", %{conn: conn} do
      tag = insert(:tag, name: "Elixir")

      conn
      |> visit(~p"/admin/tags/#{tag.id}/edit")
      |> unwrap(fn view -> view |> form("#resource-form", change: %{name: "Phoenix"}) |> render_submit() end)
      |> assert_path(~p"/admin/tags")
      |> assert_has("p", text: "Phoenix", exact: true)

      assert Repo.reload!(tag).name == "Phoenix"
    end
  end
end
