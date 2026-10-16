defmodule DemoWeb.Live.User.EmailResourceActionLiveTest do
  use DemoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  describe "email resource action" do
    test "keeps the selected users when searching before the submit", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/users/invite/resource-action")

      view
      |> element(~s(label[phx-click="toggle-option"][phx-value-id="user_id_alex"]))
      |> render_click()

      view
      |> form("#resource-form", change: %{users: ["user_id_alex"]})
      |> render_change()

      html =
        view
        |> element(~s(input[name="change[users]_search"]))
        |> render_change(%{"change[users]_search" => "bob"})

      assert html =~ "Bob"
      refute has_element?(view, ~s(label[phx-value-id="user_id_alex"]))

      view
      |> form("#resource-form", change: %{text: "Hello"})
      |> render_submit(%{"save-type" => "save"})

      {_path, flash} = assert_redirect(view)
      assert flash["info"] == "An email has been successfully sent to the specified users."
    end
  end
end
