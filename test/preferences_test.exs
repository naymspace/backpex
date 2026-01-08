defmodule Backpex.PreferencesTest do
  use ExUnit.Case, async: true

  alias Backpex.Preferences

  describe "session_key/0" do
    test "returns the session key" do
      assert Preferences.session_key() == "backpex_preferences"
    end
  end

  describe "get/3" do
    test "returns value from session" do
      session = %{
        "backpex_preferences" => %{
          "global" => %{"theme" => "dark"}
        }
      }

      assert Preferences.get(session, "global.theme") == "dark"
    end

    test "returns default when key not found" do
      session = %{}

      assert Preferences.get(session, "global.theme", default: "light") == "light"
    end

    test "returns nil when key not found and no default" do
      session = %{}

      assert Preferences.get(session, "global.theme") == nil
    end

    test "returns value from nested path" do
      session = %{
        "backpex_preferences" => %{
          "resource" => %{
            "UserLive" => %{
              "columns" => %{"name" => true, "email" => false}
            }
          }
        }
      }

      assert Preferences.get(session, "resource.UserLive.columns") == %{
               "name" => true,
               "email" => false
             }
    end

    test "returns default when intermediate path is missing" do
      session = %{
        "backpex_preferences" => %{
          "global" => %{}
        }
      }

      assert Preferences.get(session, "global.sidebar_open", default: true) == true
    end
  end

  describe "get_map/2" do
    test "returns nested map at path" do
      session = %{
        "backpex_preferences" => %{
          "global" => %{
            "sidebar_section" => %{
              "blog" => true,
              "settings" => false
            }
          }
        }
      }

      assert Preferences.get_map(session, "global.sidebar_section") == %{
               "blog" => true,
               "settings" => false
             }
    end

    test "returns empty map when path not found" do
      session = %{}

      assert Preferences.get_map(session, "global.sidebar_section") == %{}
    end

    test "returns empty map when value is not a map" do
      session = %{
        "backpex_preferences" => %{
          "global" => %{
            "theme" => "dark"
          }
        }
      }

      assert Preferences.get_map(session, "global.theme") == %{}
    end
  end

  describe "put/3" do
    test "puts value into empty map" do
      result = Preferences.put(%{}, "global.theme", "dark")

      assert result == %{"global" => %{"theme" => "dark"}}
    end

    test "preserves sibling keys" do
      prefs = %{"global" => %{"theme" => "dark"}}
      result = Preferences.put(prefs, "global.sidebar_open", true)

      assert result == %{
               "global" => %{
                 "theme" => "dark",
                 "sidebar_open" => true
               }
             }
    end

    test "creates nested path" do
      result = Preferences.put(%{}, "resource.UserLive.columns", %{"name" => true})

      assert result == %{
               "resource" => %{
                 "UserLive" => %{
                   "columns" => %{"name" => true}
                 }
               }
             }
    end

    test "overwrites existing value" do
      prefs = %{"global" => %{"theme" => "light"}}
      result = Preferences.put(prefs, "global.theme", "dark")

      assert result == %{"global" => %{"theme" => "dark"}}
    end
  end

  describe "parse_key/1" do
    test "parses dot-notation key into list" do
      assert Preferences.parse_key("global.theme") == ["global", "theme"]
    end

    test "parses multi-segment key" do
      assert Preferences.parse_key("resource.UserLive.columns") == [
               "resource",
               "UserLive",
               "columns"
             ]
    end

    test "handles single segment" do
      assert Preferences.parse_key("global") == ["global"]
    end
  end
end
