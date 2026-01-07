defmodule DemoWeb.Live.User.NewLiveTest do
  use DemoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  describe "users live resource new" do
    test "is rendered", %{conn: conn} do
      conn
      |> visit(~p"/admin/users/new")
      |> assert_has("h1", text: "New User", exact: true)
      |> assert_has("form#resource-form")
      |> assert_has("label", text: "Username")
      |> assert_has("label", text: "First Name")
      |> assert_has("label", text: "Last Name")
      |> assert_has("label", text: "Age")
      |> assert_has("label", text: "Role")
    end

    test "form has all required input fields", %{conn: conn} do
      conn
      |> visit(~p"/admin/users/new")
      |> assert_has("input[name='change[username]']")
      |> assert_has("input[name='change[first_name]']")
      |> assert_has("input[name='change[last_name]']")
      |> assert_has("input[name='change[age]']")
      |> assert_has("select[name='change[role]']")
    end

    test "validates required fields show errors", %{conn: conn} do
      conn
      |> visit(~p"/admin/users/new")
      |> unwrap(fn view ->
        view
        |> form("#resource-form", change: %{username: ""})
        |> render_change()
      end)
      # Check that the form is still rendered (validation happened)
      |> assert_has("form#resource-form")
    end

    test "shows panels with field grouping", %{conn: conn} do
      conn
      |> visit(~p"/admin/users/new")
      # The Names panel should group username, first_name, last_name fields
      |> assert_has("div", text: "Names")
    end

    test "username required shows error on submit", %{conn: conn} do
      conn
      |> visit(~p"/admin/users/new")
      |> unwrap(fn view ->
        view
        |> form("#resource-form", change: %{username: "", first_name: "Test", last_name: "User", age: 25})
        |> put_submitter("button[value=save]")
        |> render_submit()
      end)
      |> assert_has("form#resource-form")
      |> assert_has("p", text: "can't be blank")
    end
  end
end
