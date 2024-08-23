defmodule DemoWeb.LiveResourceTests do
  @moduledoc """
  Defines macros that can be used to include basic live resource tests.
  """

  @doc """
  Tests whether the table body contains expected amount of rows.
  """
  defmacro table_rows_count_test(conn, base_path, expected_rows_count) do
    quote do
      conn = unquote(conn)
      base_path = unquote(base_path)
      expected_rows_count = unquote(expected_rows_count)

      {:ok, view, _html} = live(conn, base_path)

      assert view
      |> element("table tbody")
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.find("tr")
      |> Enum.count() == expected_rows_count
    end
  end

  @doc """
  Tests whether delete button becomes enabled when clicking checkbox.
  """
  defmacro delete_button_disabled_enabled_test(conn, base_path, items) do
    quote do
      conn = unquote(conn)
      base_path = unquote(base_path)
      items = unquote(items)

      if Enum.count(items) == 0 do
        raise "Cannot test show redirect with 0 items"
      end

      {:ok, view, _html} = live(conn, base_path)

      refute has_element?(view, "button:not([disabled])", "Delete")

      [%{id: first_item_id} | _items] = items

      view
      |> element("#select-input-#{first_item_id}")
      |> render_click()

      assert has_element?(view, "button:not([disabled])", "Delete")
    end
  end

  @doc """
  Tests whether the show item action actually redirects to the show view.
  """
  defmacro show_action_redirect_test(conn, base_path, items) do
    quote do
      conn = unquote(conn)
      base_path = unquote(base_path)
      items = unquote(items)

      if Enum.count(items) == 0 do
        raise "Cannot test show redirect with 0 items"
      end

      {:ok, view, _html} = live(conn, base_path)

      [%{id: first_item_id} | _items] = items

      view
      |> element("button[aria-label='Show'][phx-value-item-id='#{first_item_id}']")
      |> render_click()

      path = assert_patch view

      assert path == "#{base_path}/#{first_item_id}/show"
    end
  end

  @doc """
  Tests whether the edit item action actually redirects to the edit view.
  """
  defmacro edit_action_redirect_test(conn, base_path, items) do
    quote do
      conn = unquote(conn)
      base_path = unquote(base_path)
      items = unquote(items)

      if Enum.count(items) == 0 do
        raise "Cannot test edit redirect with 0 items"
      end

      {:ok, view, _html} = live(conn, base_path)

      [%{id: first_item_id} | _items] = items

      view
      |> element("button[aria-label='Edit'][phx-value-item-id='#{first_item_id}']")
      |> render_click()

      path = assert_patch view

      assert path == "#{base_path}/#{first_item_id}/edit"
    end
  end
end
