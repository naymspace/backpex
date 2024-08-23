defmodule DemoWeb.TagLiveTest do
  use DemoWeb.ConnCase

  import Phoenix.LiveViewTest
  import DemoWeb.LiveResourceTests

  alias Demo.Tag
  alias Demo.Repo

  setup do
    tags =
      for entry <- data() do
        Tag.create_changeset(%Tag{}, entry)
        |> Repo.insert!()
      end

    %{tags: tags}
  end

  describe "tags live resource index" do
    test "is rendered", %{conn: conn} do
      {:ok, view, html} = live(conn, "/admin/tags")

      assert has_element?(view, "h1", "Tags")
      assert has_element?(view, "button", "New Tag")
      assert has_element?(view, "button[disabled]", "Delete")

      assert html =~ "Items 1 to 3 (3 total)"
    end

    test "delete button becomes enabled when clicking checkbox", %{conn: conn, tags: tags} do
      delete_button_disabled_enabled_test(conn, "/admin/tags", tags)
    end

    test "table body contains exact amount of rows", %{conn: conn, tags: tags} do
      table_rows_count_test(conn, "/admin/tags", Enum.count(tags))
    end

    test "show item action redirects to show view", %{conn: conn, tags: tags} do
      show_action_redirect_test(conn, "/admin/tags", tags)
    end

    test "edit item action redirects to edit view", %{conn: conn, tags: tags} do
      edit_action_redirect_test(conn, "/admin/tags", tags)
    end
  end

  defp data do
    [
      %{name: "Expert"},
      %{name: "Beginner"},
      %{name: "DIY"}
    ]
  end
end
