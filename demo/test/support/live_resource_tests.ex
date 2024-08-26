defmodule DemoWeb.LiveResourceTests do
  @moduledoc """
  Defines macros that can be used to include basic live resource tests.
  """

  @doc """
  Tests whether the table body contains expected amount of rows.
  """
  defmacro test_table_rows_count(conn, base_path, expected_rows_count) do
    quote do
      conn = unquote(conn)
      base_path = unquote(base_path)
      expected_rows_count = unquote(expected_rows_count)

      conn
      |> visit(base_path)
      |> assert_has(".table tbody tr", count: expected_rows_count)
    end
  end

  @doc """
  Tests whether delete button becomes enabled when clicking checkbox.
  """
  defmacro test_delete_button_disabled_enabled(conn, base_path, items) do
    quote do
      conn = unquote(conn)
      base_path = unquote(base_path)
      items = unquote(items)

      if Enum.empty?(items) do
        raise "Cannot test delete button with 0 items"
      end

      [%{id: first_item_id} | _items] = items

      conn
      |> visit(base_path)
      |> refute_has("button:not([disabled])", text: "Delete")
      |> assert_has("#select-input-#{first_item_id}")
      |> unwrap(fn view ->
        view
        |> element("#select-input-#{first_item_id}")
        |> render_click()
      end)
      |> assert_has("button:not([disabled])", text: "Delete", exact: true)
    end
  end

  @doc """
  Tests whether the show item action actually redirects to the show view.
  """
  defmacro test_show_action_redirect(conn, base_path, items) do
    quote do
      conn = unquote(conn)
      base_path = unquote(base_path)
      items = unquote(items)

      if Enum.empty?(items) do
        raise "Cannot test show redirect with 0 items"
      end

      [%{id: first_item_id} | _items] = items

      conn
      |> visit(base_path)
      |> unwrap(fn view ->
        view
        |> element("button[aria-label='Show'][phx-value-item-id='#{first_item_id}']")
        |> render_click()
      end)
      |> assert_path("#{base_path}/#{first_item_id}/show")
    end
  end

  @doc """
  Tests whether the edit item action actually redirects to the edit view.
  """
  defmacro test_edit_action_redirect(conn, base_path, items) do
    quote do
      conn = unquote(conn)
      base_path = unquote(base_path)
      items = unquote(items)

      if Enum.empty?(items) do
        raise "Cannot test edit redirect with 0 items"
      end

      [%{id: first_item_id} | _items] = items

      conn
      |> visit(base_path)
      |> unwrap(fn view ->
        view
        |> element("button[aria-label='Edit'][phx-value-item-id='#{first_item_id}']")
        |> render_click()
      end)
      |> assert_path("#{base_path}/#{first_item_id}/edit")
    end
  end
end
