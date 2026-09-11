defmodule Backpex.Preferences.ClientPreferencesTest do
  use ExUnit.Case, async: true

  alias Backpex.Preferences
  alias Backpex.Preferences.Context

  # Preferences the browser mirrored in sessionStorage and handed back in the
  # LiveView connect params. They describe writes made *after* the websocket
  # connected, which the frozen connect-time session cannot see — so on a read
  # they must win over whatever the adapter has stored.

  defp ctx(session, client) do
    session
    |> Context.from_mount()
    |> Context.put_client(client)
  end

  defp session(prefs), do: %{"backpex_preferences" => prefs}

  describe "get/3" do
    test "prefers a client value over the stored one" do
      ctx = ctx(session(%{"global" => %{"theme" => "light"}}), %{"global.theme" => "dark"})

      assert Preferences.get(ctx, "global.theme") == "dark"
    end

    test "falls back to the stored value for keys the client did not send" do
      ctx = ctx(session(%{"global" => %{"theme" => "light"}}), %{"global.sidebar_open" => false})

      assert Preferences.get(ctx, "global.theme") == "light"
    end

    test "a client value wins over the :default option" do
      ctx = ctx(%{}, %{"global.sidebar_open" => false})

      assert Preferences.get(ctx, "global.sidebar_open", default: true) == false
    end

    test "falls back to the :default option when neither side has the key" do
      ctx = ctx(%{}, %{})

      assert Preferences.get(ctx, "global.sidebar_open", default: true) == true
    end

    test "a client value of `false` is honored, not treated as absent" do
      # `false` and `nil` must not collapse: hiding metrics is a real preference.
      key = "resource:MyApp.UserLive:metrics_visible"
      ctx = ctx(session(%{"resource" => %{"MyApp.UserLive" => %{"metrics_visible" => true}}}), %{key => false})

      assert Preferences.get(ctx, key, default: true) == false
    end
  end

  describe "get_map/3" do
    test "merges client entries over the stored ones under the prefix" do
      stored = session(%{"global" => %{"sidebar_section" => %{"blog" => true, "users" => true}}})
      ctx = ctx(stored, %{"global.sidebar_section.blog" => false})

      assert Preferences.get_map(ctx, "global.sidebar_section") == %{"blog" => false, "users" => true}
    end

    test "adds sections the adapter has never stored" do
      ctx = ctx(%{}, %{"global.sidebar_section.blog" => false})

      assert Preferences.get_map(ctx, "global.sidebar_section") == %{"blog" => false}
    end

    test "ignores client keys outside the prefix" do
      ctx = ctx(%{}, %{"global.theme" => "dark", "global.sidebar_section.blog" => false})

      assert Preferences.get_map(ctx, "global.sidebar_section") == %{"blog" => false}
    end
  end

  describe "Context.put_client/2" do
    test "drops keys that no adapter prefix serves" do
      ctx = ctx(%{}, %{"global.theme" => "dark", "nope.key" => 1})

      assert ctx.client == %{"global.theme" => "dark"}
    end

    test "drops wrong-typed values for built-in keys" do
      # Both client carriers (connect params, `backpex_prefs` cookie) are
      # browser-written. A string where the reader expects a boolean would
      # reach a render — and `not "false"` raises, so a single planted cookie
      # would 500 every admin page until it expired. Valid entries in the same
      # payload still survive.
      ctx =
        ctx(%{}, %{
          "global.sidebar_open" => "false",
          "resource:MyApp.UserLive:metrics_visible" => "nope",
          "resource:MyApp.UserLive:columns" => %{"name" => "yes"},
          "global.theme" => "dark"
        })

      assert ctx.client == %{"global.theme" => "dark"}
    end

    test "drops non-binary keys" do
      ctx = ctx(%{}, %{:global => "dark"})

      assert ctx.client == %{}
    end

    test "treats a non-map payload as no client preferences" do
      ctx = ctx(%{}, "junk")

      assert ctx.client == %{}
    end
  end

  describe "a bare session map (no context)" do
    test "reads straight from the adapter" do
      session = session(%{"global" => %{"theme" => "light"}})

      assert Preferences.get(session, "global.theme") == "light"
    end
  end
end
