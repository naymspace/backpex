defmodule Backpex.Integration.ItemActions.PrimaryKeyPathTest do
  use Backpex.ConnCase, async: true

  # The changeset only allows URL-safe keys, but other apps use string primary keys with spaces or
  # percent signs. Insert directly to check that the show and edit links still resolve the item.
  for short_key <- ["with space", "100%", "a%20b"] do
    describe "item with primary key #{inspect(short_key)}" do
      setup do
        %{short_link: insert(:short_link, short_key: unquote(short_key), url: "https://example.com/path-test")}
      end

      test "show item action opens the show view", %{conn: conn} do
        conn
        |> visit(~p"/admin/short-links")
        |> click_link("Show")
        |> assert_has("h1", text: "Short Link", exact: true)
        |> assert_has("dd", text: unquote(short_key))
      end

      test "edit item action opens the edit view", %{conn: conn} do
        conn
        |> visit(~p"/admin/short-links")
        |> click_link("Edit")
        |> assert_has("h1", text: "Edit Short Link", exact: true)
        |> assert_has("input", label: "URL Suffix", value: unquote(short_key))
      end
    end
  end
end
