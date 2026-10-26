defmodule Backpex.E2E.ThemeSelectorTest do
  use Backpex.E2ECase, async: true

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
    |> press(@trigger, "Enter")
    |> assert_has("#backpex-theme-selector.dropdown-open")
    |> assert_a11y()
    # Tab moves from the trigger into the radio group.
    |> press(@trigger, "Tab")
    |> evaluate(@active_radio, [is_function: true], &assert(&1 == "light"))
    |> press(~s|input[name="theme-selector"][value="light"]|, "ArrowDown")
    |> evaluate(@active_radio, [is_function: true], &assert(&1 == "dark"))
    |> assert_has(~s|html[data-theme="dark"]|)
    |> evaluate(
      ~s|document.querySelector('input[name="theme-selector"][value="dark"]').checked|,
      &assert/1
    )
  end
end
