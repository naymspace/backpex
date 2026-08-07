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

  defmodule DynamicPreferencesRouter do
    use Phoenix.Router, helpers: false

    import Backpex.Router

    scope "/tenants/:tenant" do
      backpex_routes()
    end
  end

  defmodule MultiplePreferencesRouter do
    use Phoenix.Router, helpers: false

    import Backpex.Router

    scope "/admin" do
      backpex_routes()
    end

    scope "/partners" do
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
      manifest = %{"version" => 1, "routes" => [%{"kind" => "default", "token" => "abc123"}]}
      html = render_component(&Layout.preferences_root/1, socket: socket(), preferences_manifest: manifest)

      assert html =~ ~r/id="backpex-preferences"/
      assert html =~ ~r/phx-hook="BackpexPreferencesHook"/
      assert html =~ ~r|data-preferences-path="/admin/backpex_preferences"|

      assert html =~
               ~r/data-preferences-manifest="\{&quot;routes&quot;:\[\{&quot;kind&quot;:&quot;default&quot;,&quot;token&quot;:&quot;abc123&quot;\}\],&quot;version&quot;:1\}"/
    end

    test "uses an explicit endpoint path for a dynamically scoped route" do
      html =
        render_component(&Layout.preferences_root/1,
          socket: socket(),
          preferences_manifest: %{"version" => 1, "routes" => []},
          preferences_path: "/tenants/42/backpex_preferences"
        )

      assert html =~ ~r|data-preferences-path="/tenants/42/backpex_preferences"|
    end

    test "requires an explicit endpoint path for a dynamic route" do
      assert_raise ArgumentError, ~r/contains dynamic segments/, fn ->
        render_component(&Layout.preferences_root/1,
          socket: socket(DynamicPreferencesRouter),
          preferences_manifest: %{"version" => 1, "routes" => []}
        )
      end
    end

    test "requires an explicit endpoint path when the router has multiple routes" do
      assert_raise ArgumentError, ~r/Found multiple backpex_preferences routes/, fn ->
        render_component(&Layout.preferences_root/1,
          socket: socket(MultiplePreferencesRouter),
          preferences_manifest: %{"version" => 1, "routes" => []}
        )
      end
    end

    test "renders without a preferences manifest" do
      html = render_component(&Layout.preferences_root/1, socket: socket())

      assert html =~ ~r/id="backpex-preferences"/
      refute html =~ ~r/data-preferences-manifest/
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
        render_component(&Layout.app_shell/1,
          socket: socket(),
          preferences_manifest: %{
            "version" => 1,
            "routes" => [%{"kind" => "default", "token" => "abc123"}]
          },
          preferences_path: "/tenants/42/backpex_preferences",
          inner_block: []
        )

      assert html =~ ~r/id="backpex-preferences"/
      assert html =~ ~r|data-preferences-path="/tenants/42/backpex_preferences"|
      assert html =~ ~r/data-preferences-manifest=/
      assert html =~ "abc123"
    end
  end

  describe "sidebar_section/1" do
    test "hides sections without marked sidebar items before hooks mount" do
      html = sidebar_section(id: "empty")

      assert html =~ "not-has-[[data-sidebar-item]]:hidden"
      refute html =~ "<li data-sidebar-item>"
    end

    test "renders the section closed when its state says so" do
      html = sidebar_section(id: "blog", sidebar_section_states: %{"blog" => false})

      assert html =~ ~r/data-section-open="false"/
      assert html =~ ~r/aria-expanded="false"/
      assert html =~ ~r/display: none;/
    end

    test "unknown section ids default to open" do
      html = sidebar_section(id: "blog", sidebar_section_states: %{"other" => false})

      assert html =~ ~r/data-section-open="true"/
    end

    test "defaults to %{} when the attr is omitted" do
      # This is a function component, so an omitted attr cannot inherit the
      # caller's `@sidebar_section_states` assign — `assign_new/3` only ever
      # sees the attrs passed at the call site. The attr default is therefore
      # the whole story, and callers must pass the assign explicitly. Pinned
      # because the docs previously promised a parent fallback that cannot
      # exist, which silently lost every user's collapsed sections.
      html = sidebar_section(id: "blog")

      assert html =~ ~r/data-section-open="true"/
    end
  end

  describe "sidebar_item/1" do
    test "marks items so empty ancestor sections can be hidden with CSS" do
      inner_block = [%{__slot__: :inner_block, inner_block: fn _assigns, _arg -> "Posts" end}]

      html =
        render_component(&Layout.sidebar_item/1,
          current_url: "/admin/posts",
          navigate: "/admin/posts",
          inner_block: inner_block
        )

      assert html =~ ~r/<li data-sidebar-item>/
    end
  end

  defp sidebar_section(assigns) do
    label = [%{__slot__: :label, inner_block: fn _assigns, _arg -> "Blog" end}]
    render_component(&Layout.sidebar_section/1, Keyword.put_new(assigns, :label, label))
  end

  defp socket(router \\ TestRouter), do: %Phoenix.LiveView.Socket{router: router}
end
