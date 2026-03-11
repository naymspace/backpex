defmodule Demo.Support.LiveResourceTests do
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
        |> element("#item-action-show-#{first_item_id}")
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
        |> element("#item-action-edit-#{first_item_id}")
        |> render_click()
      end)
      |> assert_path("#{base_path}/#{first_item_id}/edit")
    end
  end

  @doc """
  Tests edit item action from index view with save and redirect back to index.
  """
  defmacro test_edit_from_index_save(conn, base_path, item, change_field, old_value, new_value) do
    quote do
      conn = unquote(conn)
      base_path = unquote(base_path)
      item = unquote(item)
      change_field = unquote(change_field)
      old_value = unquote(old_value)
      new_value = unquote(new_value)

      conn
      |> visit(base_path)
      |> assert_has("td", text: old_value, exact: true)
      |> unwrap(fn view ->
        view
        |> element("#item-action-edit-#{item.id}")
        |> render_click()
      end)
      |> assert_path("#{base_path}/#{item.id}/edit")
      |> unwrap(fn view ->
        view
        |> form("#resource-form", change: %{change_field => new_value})
        |> put_submitter("button[value=save]")
        |> render_submit()
      end)
      |> assert_path(base_path)
      |> assert_has("td", text: new_value, exact: true)
    end
  end

  @doc """
  Tests edit item action from index view with cancel and redirect back to index.
  """
  defmacro test_edit_from_index_cancel(conn, base_path, item, display_field, display_value) do
    quote do
      conn = unquote(conn)
      base_path = unquote(base_path)
      item = unquote(item)
      display_field = unquote(display_field)
      display_value = unquote(display_value)

      conn
      |> visit(base_path)
      |> assert_has("td", text: display_value, exact: true)
      |> unwrap(fn view ->
        view
        |> element("#item-action-edit-#{item.id}")
        |> render_click()
      end)
      |> assert_path("#{base_path}/#{item.id}/edit")
      |> unwrap(fn view ->
        view
        |> element("a:has(button[value='cancel'])")
        |> render_click()
      end)
      |> assert_path(base_path)
      |> assert_has("td", text: display_value, exact: true)
    end
  end

  @doc """
  Tests edit item action from show view with save and redirect back to show.
  """
  defmacro test_edit_from_show_save(conn, base_path, item, change_field, old_value, new_value) do
    quote do
      conn = unquote(conn)
      base_path = unquote(base_path)
      item = unquote(item)
      change_field = unquote(change_field)
      old_value = unquote(old_value)
      new_value = unquote(new_value)

      conn
      |> visit("#{base_path}/#{item.id}/show")
      |> assert_has("dd", text: old_value, exact: true)
      |> assert_has("#item-action-edit")
      |> unwrap(fn view ->
        view
        |> element("#item-action-edit")
        |> render_click()
      end)
      |> assert_path("#{base_path}/#{item.id}/edit")
      |> unwrap(fn view ->
        view
        |> form("#resource-form", change: %{change_field => new_value})
        |> put_submitter("button[value=save]")
        |> render_submit()
      end)
      |> assert_path("#{base_path}/#{item.id}/show")
      |> assert_has("dd", text: new_value, exact: true)
    end
  end

  @doc """
  Tests edit item action from show view with cancel and redirect back to show.
  """
  defmacro test_edit_from_show_cancel(conn, base_path, item, display_field, display_value) do
    quote do
      conn = unquote(conn)
      base_path = unquote(base_path)
      item = unquote(item)
      display_field = unquote(display_field)
      display_value = unquote(display_value)

      conn
      |> visit("#{base_path}/#{item.id}/show")
      |> assert_has("dd", text: display_value, exact: true)
      |> assert_has("#item-action-edit")
      |> unwrap(fn view ->
        view
        |> element("#item-action-edit")
        |> render_click()
      end)
      |> assert_path("#{base_path}/#{item.id}/edit")
      |> unwrap(fn view ->
        view
        |> element("a:has(button[value='cancel'])")
        |> render_click()
      end)
      |> assert_path("#{base_path}/#{item.id}/show")
      |> assert_has("dd", text: display_value, exact: true)
    end
  end

  @doc """
  Tests delete item action from index view.
  """
  defmacro test_delete_from_index(conn, base_path, item, display_field, display_value, success_message \\ nil) do
    quote do
      conn = unquote(conn)
      base_path = unquote(base_path)
      item = unquote(item)
      display_field = unquote(display_field)
      display_value = unquote(display_value)

      result =
        conn
        |> visit(base_path)
        |> assert_has("td", text: display_value, exact: true)
        |> unwrap(fn view ->
          view
          |> element("button[aria-label='Delete'][phx-value-item-id='#{item.id}']")
          |> render_click()
        end)
        |> unwrap(fn view ->
          view
          |> form("#resource-form")
          |> render_submit()
        end)
        |> assert_path(base_path)
        |> refute_has("td", text: display_value, exact: true)

      case unquote(success_message) do
        message when is_nil(message) ->
          result

        message ->
          result |> assert_has("div", text: message, exact: true)
      end
    end
  end

  @doc """
  Tests delete item action from show view.
  """
  defmacro test_delete_from_show(conn, base_path, item, display_field, display_value, success_message \\ nil) do
    quote do
      conn = unquote(conn)
      base_path = unquote(base_path)
      item = unquote(item)
      display_field = unquote(display_field)
      display_value = unquote(display_value)

      result =
        conn
        |> visit("#{base_path}/#{item.id}/show")
        |> assert_has("dd", text: display_value, exact: true)
        |> assert_has("#item-action-delete")
        |> unwrap(fn view ->
          view
          |> element("#item-action-delete")
          |> render_click()
        end)
        |> unwrap(fn view ->
          view
          |> form("#resource-form")
          |> render_submit()
        end)
        |> assert_path(base_path)
        |> refute_has("td", text: display_value, exact: true)

      case unquote(success_message) do
        message when is_nil(message) ->
          result

        message ->
          result |> assert_has("div", text: message, exact: true)
      end
    end
  end

  @doc """
  Tests that search filters results correctly.
  Performs a search and verifies the expected number of rows remain.
  """
  defmacro test_search_filters_results(conn, base_path, search_term, expected_count) do
    quote do
      conn = unquote(conn)
      base_path = unquote(base_path)
      search_term = unquote(search_term)
      expected_count = unquote(expected_count)

      conn
      |> visit(base_path)
      |> unwrap(fn view ->
        view
        |> form("#index-search-form", index_search: %{value: search_term})
        |> render_change()
      end)
      |> assert_has("table tbody tr", count: expected_count)
    end
  end

  @doc """
  Tests that a metric displays the expected label and value.
  """
  defmacro test_metric_displays(conn, base_path, metric_label, expected_value) do
    quote do
      conn = unquote(conn)
      base_path = unquote(base_path)
      metric_label = unquote(metric_label)
      expected_value = unquote(expected_value)

      conn
      |> visit(base_path)
      |> assert_has("div", text: metric_label)
      |> assert_has("div", text: expected_value)
    end
  end

  @doc """
  Tests that an item action button is NOT available for an item.
  Useful for testing authorization (can? returning false).
  """
  defmacro test_action_not_available(conn, base_path, item, action_label) do
    quote do
      conn = unquote(conn)
      base_path = unquote(base_path)
      item = unquote(item)
      action_label = unquote(action_label)

      conn
      |> visit(base_path)
      |> refute_has("button[aria-label='#{action_label}'][phx-value-item-id='#{item.id}']")
    end
  end

  @doc """
  Tests that an item action button IS available for an item.
  """
  defmacro test_action_available(conn, base_path, item, action_label) do
    quote do
      conn = unquote(conn)
      base_path = unquote(base_path)
      item = unquote(item)
      action_label = unquote(action_label)

      conn
      |> visit(base_path)
      |> assert_has("button[aria-label='#{action_label}'][phx-value-item-id='#{item.id}']")
    end
  end

  @doc """
  Tests that a resource button (like "New Resource") is NOT available.
  """
  defmacro test_resource_button_not_available(conn, base_path, button_text) do
    quote do
      conn = unquote(conn)
      base_path = unquote(base_path)
      button_text = unquote(button_text)

      conn
      |> visit(base_path)
      |> refute_has("button", text: button_text)
    end
  end
end
