defmodule Backpex.Integration.Fields.MultiSelectTest do
  use Backpex.ConnCase, async: true

  import Phoenix.LiveViewTest

  @search "#multi_select input[type=search]"

  describe "search in the form" do
    test "is kept when an option is selected", %{conn: conn} do
      conn
      |> visit(~p"/admin/samples/new")
      |> unwrap(fn view ->
        view |> element(@search) |> render_change(%{"change[multi_select]_search" => "re"})
      end)
      |> assert_has("#multi_select label", count: 2)
      # Ticking an option is a change of the form, which validates and renders all of its fields again.
      |> unwrap(fn view ->
        view
        |> form("#resource-form", %{change: %{multi_select: ["red"]}})
        |> render_change(%{_target: ["change", "multi_select", ""]})
      end)
      |> assert_has("#multi_select input[type=checkbox][value=red][checked]")
      |> assert_has(@search <> "[value=re]")
      |> assert_has("#multi_select label", count: 2)
      |> assert_has("#multi_select label", text: "Red")
      |> assert_has("#multi_select label", text: "Green")
    end
  end

  test "shows the selected options on the index and show views", %{conn: conn} do
    sample = insert(:sample, multi_select: ["red", "blue"])

    for path <- [~p"/admin/samples", ~p"/admin/samples/#{sample.id}/show"] do
      conn
      |> visit(path)
      |> assert_has(".badge", text: "Red")
      |> assert_has(".badge", text: "Blue")
      |> refute_has(".badge", text: "Green")
    end
  end
end
