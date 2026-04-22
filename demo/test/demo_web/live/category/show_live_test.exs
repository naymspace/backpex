defmodule DemoWeb.Live.Category.ShowLiveTest do
  use DemoWeb.ConnCase, async: false

  import Demo.EctoFactory

  describe "categories live resource show" do
    test "is rendered", %{conn: conn} do
      category = insert(:category)

      conn
      |> visit(~p"/admin/categories/#{category.id}/show")
      |> assert_has("h1", text: "Category", exact: true)
      |> assert_has("dt", text: "Name", exact: true)
      |> assert_has("dd", text: category.name, exact: true)
    end
  end
end
