defmodule DemoWeb.Live.Tag.EditItemActionLiveTest do
  use DemoWeb.ConnCase, async: false

  import Demo.EctoFactory
  import Phoenix.LiveViewTest
  import Demo.Support.LiveResourceTests

  describe "edit item action on index view" do
    test "redirects to index view", %{conn: conn} do
      tag = insert(:tag, name: "Elixir")

      test_edit_from_index_save(
        conn,
        ~p"/admin/tags",
        tag,
        :name,
        "Elixir",
        "Updated Elixir"
      )
    end

    test "redirects to index view on cancel", %{conn: conn} do
      tag = insert(:tag, name: "Elixir")

      test_edit_from_index_cancel(
        conn,
        ~p"/admin/tags",
        tag,
        :name,
        "Elixir"
      )
    end
  end

  describe "edit item action on show view" do
    test "redirects to show view", %{conn: conn} do
      tag = insert(:tag, name: "Elixir")

      test_edit_from_show_save(
        conn,
        ~p"/admin/tags",
        tag,
        :name,
        "Elixir",
        "Updated Elixir"
      )
    end

    test "redirects to show view on cancel", %{conn: conn} do
      tag = insert(:tag, name: "Elixir")

      test_edit_from_show_cancel(
        conn,
        ~p"/admin/tags",
        tag,
        :name,
        "Elixir"
      )
    end
  end
end
