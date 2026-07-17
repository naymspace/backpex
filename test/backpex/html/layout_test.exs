defmodule Backpex.HTML.LayoutTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias Backpex.HTML.Layout

  defmodule TestRouter do
    use Phoenix.Router, helpers: false

    import Backpex.Router

    scope "/admin" do
      backpex_routes()
    end
  end

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

  describe "preferences_root/1" do
    test "renders the endpoint path the JS hook needs to persist anything" do
      html = render_component(&Layout.preferences_root/1, socket: socket(), preferences_identity: "abc123")

      assert html =~ ~r/id="backpex-preferences"/
      assert html =~ ~r/phx-hook="BackpexPreferencesHook"/
      assert html =~ ~r|data-preferences-path="/admin/backpex_preferences"|
      assert html =~ ~r/data-preferences-identity="abc123"/
    end

    test "renders without an identity" do
      html = render_component(&Layout.preferences_root/1, socket: socket())

      assert html =~ ~r/id="backpex-preferences"/
      refute html =~ ~r/data-preferences-identity/
    end
  end

  describe "app_shell/1" do
    test "renders preferences_root so preference writes reach the server" do
      # Without this element on the page the JS hook has no endpoint to POST to
      # and drops every write — theme, sidebar, sidebar sections, and the
      # LiveResource `persist:` keys — with only a console warning. Layouts that
      # do not use app_shell/1 must render `preferences_root/1` themselves; this
      # asserts the app_shell path stays wired.
      html =
        render_component(&Layout.app_shell/1, socket: socket(), preferences_identity: "abc123", inner_block: [])

      assert html =~ ~r/id="backpex-preferences"/
      assert html =~ ~r|data-preferences-path="/admin/backpex_preferences"|
      assert html =~ ~r/data-preferences-identity="abc123"/
    end
  end

  defp socket, do: %Phoenix.LiveView.Socket{router: TestRouter}
end
