defmodule Backpex.Integration.ResourceActions.FormTest do
  use Backpex.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "with a multi select field" do
    test "keeps the selected options when searching before the submit", %{conn: conn} do
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

  # The browser doesn't submit a form while a file input has refused files, but a save event can still reach the server.
  describe "with an upload field that has refused files" do
    test "refuses the save", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/users/upload/resource-action")

      view
      |> file_input("#resource-form", :upload, [%{name: "notes.txt", content: "notes", type: "text/plain"}])
      |> render_upload("notes.txt")

      html =
        view
        |> form("#resource-form", change: %{description: "Notes"})
        |> render_submit(%{"save-type" => "save"})

      # The action requires a file, so without the check the save is refused as blank and nothing crashes.
      assert has_element?(view, "#upload-drop-target + section > p", "can't be blank")
      assert has_element?(view, "#upload-drop-target + section > p", "remove the files that can't be uploaded")
      refute html =~ "File was uploaded successfully."
    end
  end
end
