defmodule DemoWeb.Live.User.FilterLiveTest do
  use DemoWeb.ConnCase, async: false

  import Demo.EctoFactory
  import Phoenix.LiveViewTest

  describe "select filter configured in the LiveResource" do
    test "renders the options of its configuration", %{conn: conn} do
      conn
      |> visit(~p"/admin/users")
      |> assert_has("select[name='filters[role]'] option", text: "Select an option...")
      |> assert_has("select[name='filters[role]'] option[value='admin']", text: "Admin")
      |> assert_has("select[name='filters[age]'] option[value='minor']", text: "Under 18")
    end

    test "filters users by an enum value", %{conn: conn} do
      insert(:user, first_name: "Paula", last_name: "Plain", role: :user)
      insert(:user, first_name: "Ada", last_name: "Admin", role: :admin)

      conn
      |> visit(~p"/admin/users")
      |> assert_has("table tbody tr", count: 2)
      |> unwrap(fn view ->
        view
        |> form("form[phx-change='change-filter']", filters: %{role: "admin"})
        |> render_change()
      end)
      |> assert_has("table tbody tr", count: 1)
      |> assert_has("td", text: "Ada Admin")
      |> refute_has("td", text: "Paula Plain")
    end

    test "rejects a value that is not an option", %{conn: conn} do
      insert(:user, role: :user)

      conn
      |> visit(~p"/admin/users?#{%{"filters" => %{"role" => "owner"}}}")
      |> assert_has("table tbody tr", count: 1)
      |> assert_has("#filter-form", text: "is not a valid option")
    end
  end

  describe "condition option" do
    test "keeps the items that match the condition of the selected option", %{conn: conn} do
      insert(:user, first_name: "Yuri", last_name: "Young", age: 16)
      insert(:user, first_name: "Ada", last_name: "Adult", age: 30)

      conn
      |> visit(~p"/admin/users?#{%{"filters" => %{"age" => "minor"}}}")
      |> assert_has("table tbody tr", count: 1)
      |> assert_has("td", text: "Yuri Young")
      |> refute_has("td", text: "Ada Adult")
      |> visit(~p"/admin/users?#{%{"filters" => %{"age" => "adult"}}}")
      |> assert_has("table tbody tr", count: 1)
      |> assert_has("td", text: "Ada Adult")
      |> refute_has("td", text: "Yuri Young")
    end
  end
end
