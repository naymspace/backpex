defmodule DemoWeb.Live.Tag.ShowLiveTest do
  use DemoWeb.ConnCase, async: false

  import Demo.EctoFactory

  describe "tags live resource show" do
    test "is rendered", %{conn: conn} do
      tag = insert(:tag)

      conn
      |> visit(~p"/admin/tags/#{tag.id}/show")
      |> assert_has("h1", text: "Tag", exact: true)
      |> assert_has("dt", text: "Name", exact: true)
      |> assert_has("dt", text: "Inserted At", exact: true)
      |> assert_has("dd", text: tag.name, exact: true)
    end
  end
end
