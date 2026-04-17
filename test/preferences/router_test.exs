defmodule Backpex.Preferences.RouterTest do
  use ExUnit.Case, async: false

  alias Backpex.Preferences.Adapters.Session
  alias Backpex.Preferences.Router

  describe "routes/0 with no configured adapters" do
    setup do
      prior = Application.get_env(:backpex, Backpex.Preferences)
      on_exit(fn -> restore_env(prior) end)
      Application.delete_env(:backpex, Backpex.Preferences)
      :ok
    end

    test "falls back to a single :default Session route" do
      assert Router.routes() == [{:default, Session, []}]
    end
  end

  describe "resolve/2" do
    test "selects the most specific wildcard pattern" do
      routes = [
        {"global.*", SessionA, []},
        {"resource.*", AdapterB, []},
        {:default, FallbackAdapter, []}
      ]

      assert {SessionA, []} = Router.resolve("global.theme", routes)
      assert {AdapterB, []} = Router.resolve("resource:MyApp.MyLive:columns", routes)
    end

    test "picks the exact pattern over a wildcard regardless of config order" do
      routes = [
        {"global.*", Wildcard, []},
        {"global.theme", Specific, foo: :bar}
      ]

      assert {Specific, [foo: :bar]} = Router.resolve("global.theme", routes)
    end

    test "falls back to :default when no key-specific pattern matches" do
      routes = [
        {"global.*", GlobalAdapter, []},
        {:default, DefaultAdapter, []}
      ]

      assert {DefaultAdapter, []} = Router.resolve("custom.whatever", routes)
    end

    test "raises ArgumentError when nothing (not even :default) matches" do
      routes = [{"global.*", Adapter, []}]

      assert_raise ArgumentError, ~r/no Backpex.Preferences adapter matches key/, fn ->
        Router.resolve("resource.foo", routes)
      end
    end

    test "accepts two-tuple routes (module without opts)" do
      routes = [{:default, Session}]
      assert {Session, []} = Router.resolve("anything", Router.default_routes() ++ routes)
    end
  end

  defp restore_env(nil), do: Application.delete_env(:backpex, Backpex.Preferences)
  defp restore_env(value), do: Application.put_env(:backpex, Backpex.Preferences, value)
end
