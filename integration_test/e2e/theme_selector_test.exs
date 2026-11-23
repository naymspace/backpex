defmodule Backpex.E2E.ThemeSelectorTest do
  use Backpex.E2ECase, async: true

  alias Playwright.Page

  @trigger "#backpex-theme-selector-trigger"

  @active_radio """
  () => {
    const element = document.activeElement
    return element.matches('input[name="theme-selector"]') ? element.value : null
  }
  """

  test "selects a theme with the keyboard", %{conn: conn} do
    conn
    |> visit(~p"/admin/posts")
    |> assert_has("body .phx-connected")
    |> assert_has(~s|html[data-theme="light"]|)
    |> unwrap(&Page.press!(&1, @trigger, "Enter"))
    |> assert_has("#backpex-theme-selector.dropdown-open")
    |> assert_a11y()
    # Tab moves from the trigger into the radio group.
    |> unwrap(&Page.press!(&1, @trigger, "Tab"))
    |> unwrap(&assert(Page.evaluate!(&1, @active_radio) == "light"))
    |> unwrap(&Page.press!(&1, ~s|input[name="theme-selector"][value="light"]|, "ArrowDown"))
    |> unwrap(&assert(Page.evaluate!(&1, @active_radio) == "dark"))
    |> assert_has(~s|html[data-theme="dark"]|)
    |> unwrap(
      &assert(Page.evaluate!(&1, ~s|document.querySelector('input[name="theme-selector"][value="dark"]').checked|))
    )
  end
end
