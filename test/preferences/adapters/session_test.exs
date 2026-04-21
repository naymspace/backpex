defmodule Backpex.Preferences.Adapters.SessionTest do
  use ExUnit.Case, async: true

  alias Backpex.Preferences.Adapters.Session
  alias Backpex.Preferences.Context
  alias Backpex.Preferences.Keys

  describe "get/3" do
    test "returns {:ok, value} when the path is populated" do
      ctx = Context.from_mount(%{"backpex_preferences" => %{"global" => %{"theme" => "dark"}}})
      assert Session.get(ctx, Keys.theme(), []) == {:ok, "dark"}
    end

    test "returns {:ok, :not_found} when the path is missing" do
      ctx = Context.from_mount(%{})
      assert Session.get(ctx, Keys.theme(), []) == {:ok, :not_found}
    end

    test "returns {:ok, :not_found} when an intermediate segment is missing" do
      ctx = Context.from_mount(%{"backpex_preferences" => %{"global" => %{}}})
      assert Session.get(ctx, Keys.theme(), []) == {:ok, :not_found}
    end

    test "handles colon-form keys without dot-collision" do
      ctx =
        Context.from_mount(%{
          "backpex_preferences" => %{
            "resource" => %{"MyApp.MyLive" => %{"columns" => %{"name" => true}}}
          }
        })

      assert Session.get(ctx, Keys.columns(MyApp.MyLive), []) == {:ok, %{"name" => true}}
    end
  end

  describe "get_map/3" do
    test "returns the nested map at the prefix" do
      ctx =
        Context.from_mount(%{
          "backpex_preferences" => %{"global" => %{"sidebar_section" => %{"blog" => true}}}
        })

      assert Session.get_map(ctx, Keys.sidebar_section_prefix(), []) == {:ok, %{"blog" => true}}
    end

    test "returns {:ok, %{}} when the prefix is absent" do
      ctx = Context.from_mount(%{})
      assert Session.get_map(ctx, Keys.sidebar_section_prefix(), []) == {:ok, %{}}
    end

    test "returns {:ok, %{}} when the value at the prefix is not a map" do
      ctx = Context.from_mount(%{"backpex_preferences" => %{"global" => %{"theme" => "dark"}}})
      assert Session.get_map(ctx, Keys.theme(), []) == {:ok, %{}}
    end
  end

  describe "put/4" do
    test "returns a :put_session effect that merges into the existing session tree" do
      ctx =
        %{Context.from_mount(%{"backpex_preferences" => %{"global" => %{"theme" => "light"}}}) | source: :controller}

      assert {:ok, [{:put_session, "backpex_preferences", merged}]} =
               Session.put(ctx, Keys.sidebar_open(), true, [])

      assert merged == %{"global" => %{"theme" => "light", "sidebar_open" => true}}
    end

    test "returns {:error, :requires_http} for mount/server sources" do
      ctx = Context.from_mount(%{})
      assert Session.put(ctx, Keys.theme(), "dark", []) == {:error, :requires_http}

      ctx = Context.from_socket(%{}, %{})
      assert Session.put(ctx, Keys.theme(), "dark", []) == {:error, :requires_http}
    end
  end
end
