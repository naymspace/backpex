defmodule Backpex.Integration.ResourceActions.FormTest do
  use Backpex.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "with a multi select field" do
    test "keeps the selected options when searching before the submit", %{conn: conn} do
      conn
      |> visit(~p"/admin/users/invite/resource-action")
      |> check("Alex")
      # The search input of the multi select has no label, so phoenix_test can't fill it in.
      |> unwrap(fn view ->
        view
        |> element(~s(input[name="change[users]_search"]))
        |> render_change(%{"change[users]_search" => "bob"})
      end)
      |> assert_has("label", text: "Bob")
      |> refute_has("label", text: "Alex")
      # phoenix_test remembers the checked option, so the test checks that the form still sends it on its own.
      |> assert_has(~s(input[type="hidden"][name="change[users][]"][value="user_id_alex"]))
      |> within("#resource-form", fn session ->
        session
        |> fill_in("Text", with: "Hello")
        |> click_button("Send email")
      end)
      |> assert_has("div", text: "An email has been successfully sent to the specified users.")
    end
  end

  # The browser doesn't submit a form while a file input has refused files, but a save event can still reach the server.
  describe "with an upload field that has refused files" do
    test "refuses the save", %{conn: conn} do
      conn
      |> visit(~p"/admin/users/upload/resource-action")
      # phoenix_test raises on a refused file, so the test uploads with LiveViewTest.
      |> unwrap(fn view ->
        view
        |> file_input("#resource-form", :upload, [%{name: "notes.txt", content: "notes", type: "text/plain"}])
        |> render_upload("notes.txt")

        render(view)
      end)
      |> fill_in("Description", with: "Notes")
      |> unwrap(fn view -> view |> form("#resource-form") |> render_submit(%{"save-type" => "save"}) end)
      # The action requires a file, so without the check the save is refused as blank and nothing crashes.
      |> assert_path(~p"/admin/users/upload/resource-action")
      |> assert_has("#upload-drop-target + section > p", text: "can't be blank")
      |> assert_has("#upload-drop-target + section > p", text: "remove the files that can't be uploaded")
      |> refute_has("div", text: "File was uploaded successfully.")
    end
  end
end
