defmodule DemoWeb.Live.User.UploadResourceActionLiveTest do
  use DemoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  # The browser doesn't submit a form while a file input has refused files, but a save event can still reach the server.
  describe "upload resource action with refused files" do
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

  describe "upload resource action" do
    test "runs the action with the file", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/users/upload/resource-action")

      view
      |> file_input("#resource-form", :upload, [%{name: "photo.jpg", content: "photo", type: "image/jpeg"}])
      |> render_upload("photo.jpg")

      view
      |> form("#resource-form", change: %{description: "Photo"})
      |> render_submit(%{"save-type" => "save"})

      assert {_path, %{"info" => "File was uploaded successfully."}} = assert_redirect(view)
    end
  end
end
