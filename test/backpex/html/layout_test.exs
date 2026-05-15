defmodule Backpex.HTML.LayoutTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias Backpex.HTML.Layout

  describe "theme_selector/1" do
    test "mounts the theme hook on the inner form, not on the dropdown wrapper" do
      # Regression: the <.dropdown> component hardcodes
      # phx-hook="BackpexDropdown" on its root, so passing
      # phx-hook="BackpexThemeSelector" via @rest produced a duplicate
      # attribute that the browser silently dropped. The theme hook must
      # live on the inner form element instead.
      html =
        render_component(&Layout.theme_selector/1,
          current_theme: "light",
          label: "Theme",
          themes: [{"Light", "light"}, {"Dark", "dark"}]
        )

      # The dropdown wrapper exists and still owns BackpexDropdown.
      assert html =~ ~r/<div\s+id="backpex-theme-selector"[^>]*phx-hook="BackpexDropdown"/
      # ...and does NOT also carry the theme hook.
      refute html =~ ~r/<div\s+id="backpex-theme-selector"[^>]*phx-hook="BackpexThemeSelector"/

      # The form owns BackpexThemeSelector.
      assert html =~
               ~r/<form\s+id="backpex-theme-selector-form"[^>]*phx-hook="BackpexThemeSelector"/

      # Exactly one occurrence of each hook in the rendered fragment —
      # guards against any future duplicate-attribute regression.
      assert length(Regex.scan(~r/phx-hook="BackpexDropdown"/, html)) == 1
      assert length(Regex.scan(~r/phx-hook="BackpexThemeSelector"/, html)) == 1
    end
  end
end
