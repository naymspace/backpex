defmodule Backpex.PreferencesTest do
  use ExUnit.Case, async: true

  alias Backpex.Preferences
  alias Backpex.Preferences.Adapters.Session
  alias Backpex.Preferences.Context

  describe "session_key/0" do
    test "returns the session key used by the session adapter" do
      assert Preferences.session_key() == Session.session_key()
      assert Preferences.session_key() == "backpex_preferences"
    end
  end

  describe "get/3 (session map form)" do
    test "reads a value from the backing session" do
      session = %{"backpex_preferences" => %{"global" => %{"theme" => "dark"}}}
      assert Preferences.get(session, "global.theme") == "dark"
    end

    test "returns the :default option when the key is missing" do
      assert Preferences.get(%{}, "global.theme", default: "light") == "light"
    end

    test "returns nil when the key is missing and no default is set" do
      assert Preferences.get(%{}, "global.theme") == nil
    end

    test "reads colon-form keys without dot-collision on embedded module names" do
      session = %{
        "backpex_preferences" => %{
          "resource" => %{
            "MyApp.UserLive" => %{"columns" => %{"name" => true}}
          }
        }
      }

      assert Preferences.get(session, "resource:MyApp.UserLive:columns") == %{"name" => true}
    end
  end

  describe "get/3 (Context form)" do
    test "accepts a Context built from a session map" do
      session = %{"backpex_preferences" => %{"global" => %{"theme" => "dark"}}}
      ctx = Context.from_mount(session)
      assert Preferences.get(ctx, "global.theme") == "dark"
    end
  end

  describe "get_map/3" do
    test "returns the nested map at the given prefix" do
      session = %{
        "backpex_preferences" => %{
          "global" => %{"sidebar_section" => %{"blog" => true, "settings" => false}}
        }
      }

      assert Preferences.get_map(session, "global.sidebar_section") == %{
               "blog" => true,
               "settings" => false
             }
    end

    test "returns an empty map when the prefix is absent" do
      assert Preferences.get_map(%{}, "global.sidebar_section") == %{}
    end

    test "returns an empty map when the value at the prefix is not a map" do
      session = %{"backpex_preferences" => %{"global" => %{"theme" => "dark"}}}
      assert Preferences.get_map(session, "global.theme") == %{}
    end
  end

  describe "put_batch/2" do
    test "returns side effects that compose across writes to the same session key" do
      ctx = Context.from_mount(%{"backpex_preferences" => %{"global" => %{"theme" => "light"}}})

      entries = [
        {"global.theme", "dark"},
        {"global.sidebar_open", true}
      ]

      # Pretend we're in a controller so the Session adapter will emit put_session effects.
      ctx = %{ctx | source: :controller}

      assert {:ok, effects} = Preferences.put_batch(ctx, entries)

      # The last put_session effect carries the fully-merged map.
      last_effect = List.last(effects)
      assert {:put_session, "backpex_preferences", merged} = last_effect
      assert merged == %{"global" => %{"theme" => "dark", "sidebar_open" => true}}
    end

    test "returns {:error, list} when any adapter refuses a write (all-or-nothing)" do
      # :mount source → Session adapter returns :requires_http.
      ctx = Context.from_mount(%{})
      assert {:error, errors} = Preferences.put_batch(ctx, [{"global.theme", "dark"}])
      assert [{"global.theme", :requires_http}] = errors
    end
  end

  describe "parse_key/1 (legacy alias)" do
    test "delegates to Backpex.Preferences.Key" do
      assert Preferences.parse_key("global.theme") == ["global", "theme"]
      assert Preferences.parse_key("resource:MyApp.UserLive:columns") == ["resource", "MyApp.UserLive", "columns"]
    end
  end
end
