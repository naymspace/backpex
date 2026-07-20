defmodule Backpex.Preferences.AdapterTest do
  use ExUnit.Case, async: true

  alias Backpex.Preferences.Adapter

  doctest Adapter

  describe "nest/2" do
    test "keys the result by the segments below the prefix" do
      rows = [{"global.sidebar_section.blog", true}, {"global.sidebar_section.users", false}]

      assert Adapter.nest(rows, "global.sidebar_section") == %{"blog" => true, "users" => false}
    end

    test "builds intermediate levels for deeper rows" do
      rows = [{"global.sidebar_section.blog", true}, {"global.sidebar_open", false}]

      assert Adapter.nest(rows, "global") == %{
               "sidebar_open" => false,
               "sidebar_section" => %{"blog" => true}
             }
    end

    test "splits colon-form keys on colons" do
      rows = [{"resource:MyApp.PostLive:columns", %{"title" => true}}]

      assert Adapter.nest(rows, "resource") == %{"MyApp.PostLive" => %{"columns" => %{"title" => true}}}
    end

    test "drops a row whose key is the prefix itself" do
      assert Adapter.nest([{"global", "whatever"}], "global") == %{}
    end

    test "drops rows that only match the prefix mid-segment" do
      rows = [{"global.sidebarXsection.blog", true}, {"global.sidebar_section.blog", false}]

      assert Adapter.nest(rows, "global.sidebar_section") == %{"blog" => false}
    end

    test "drops rows under a different prefix entirely" do
      assert Adapter.nest([{"resource:PostLive:order", %{}}], "global") == %{}
    end

    test "returns an empty map for no rows" do
      assert Adapter.nest([], "global") == %{}
    end
  end

  describe "deep_put/3" do
    test "writes at the top level" do
      assert Adapter.deep_put(%{}, ["a"], 1) == %{"a" => 1}
    end

    test "creates missing intermediate maps" do
      assert Adapter.deep_put(%{}, ["a", "b", "c"], 1) == %{"a" => %{"b" => %{"c" => 1}}}
    end

    test "preserves siblings while descending" do
      map = %{"a" => %{"keep" => 1}}

      assert Adapter.deep_put(map, ["a", "b"], 2) == %{"a" => %{"keep" => 1, "b" => 2}}
    end

    test "replaces a leaf standing where a branch is needed" do
      assert Adapter.deep_put(%{"a" => 1}, ["a", "b"], 2) == %{"a" => %{"b" => 2}}
    end
  end
end
