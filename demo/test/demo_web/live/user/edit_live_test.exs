defmodule DemoWeb.Live.User.EditLiveTest do
  use DemoWeb.ConnCase, async: false

  import Demo.EctoFactory
  import Phoenix.LiveViewTest

  describe "users live resource edit" do
    test "is rendered", %{conn: conn} do
      user = insert(:user)

      conn
      |> visit(~p"/admin/users/#{user.id}/edit")
      |> assert_has("h1", text: "Edit User", exact: true)
      |> assert_has("form#resource-form")
    end

    test "pre-populates form with existing user data", %{conn: conn} do
      user = insert(:user, %{username: "existinguser", first_name: "Existing", last_name: "User", age: 42})

      conn
      |> visit(~p"/admin/users/#{user.id}/edit")
      |> assert_has("input[name='change[username]'][value='existinguser']")
      |> assert_has("input[name='change[first_name]'][value='Existing']")
      |> assert_has("input[name='change[last_name]'][value='User']")
      |> assert_has("input[name='change[age]'][value='42']")
    end

    test "form has all input fields", %{conn: conn} do
      user = insert(:user)

      conn
      |> visit(~p"/admin/users/#{user.id}/edit")
      |> assert_has("input[name='change[username]']")
      |> assert_has("input[name='change[first_name]']")
      |> assert_has("input[name='change[last_name]']")
      |> assert_has("input[name='change[age]']")
      |> assert_has("select[name='change[role]']")
    end

    test "editing with invalid data shows error", %{conn: conn} do
      user = insert(:user, %{username: "testuser", first_name: "Test", last_name: "User", age: 25})

      conn
      |> visit(~p"/admin/users/#{user.id}/edit")
      |> unwrap(fn view ->
        view
        |> form("#resource-form", change: %{username: ""})
        |> put_submitter("button[value=save]")
        |> render_submit()
      end)
      |> assert_has("form#resource-form")
      |> assert_has("p", text: "can't be blank")
    end
  end
end
