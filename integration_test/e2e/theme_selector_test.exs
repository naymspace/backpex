defmodule Backpex.E2E.ThemeSelectorTest do
  use Backpex.E2ECase, async: true

  @trigger "#backpex-theme-selector-trigger"

  test "selects a theme with the keyboard", %{session: session} do
    light = by_role(:radio, name: "Light", exact: true)
    dark = by_role(:radio, name: "Dark", exact: true)

    session
    |> visit(~p"/admin/posts")
    |> assert(attribute(by_css("html"), "data-theme", "light"))
    |> press(by_css(@trigger), "Enter")
    |> assert_has(by_css("#backpex-theme-selector.dropdown-open"))
    |> assert_a11y()
    # Tab moves from the trigger into the radio group.
    |> press(by_css(@trigger), "Tab")
    |> assert(focused(light))
    |> press(light, "ArrowDown")
    |> assert(focused(dark))
    |> assert(attribute(by_css("html"), "data-theme", "dark"))
    |> assert(checked(dark))
  end
end
