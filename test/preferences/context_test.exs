defmodule Backpex.Preferences.ContextTest do
  @moduledoc """
  Targeted coverage for `Backpex.Preferences.Context.coerce/1`.

  Each clause of `coerce/1` has a distinct behavior that callers rely on
  (pass-through, wrap, raise on atom-keyed maps, raise on non-map terms),
  and the branches were previously only exercised indirectly through
  higher-level tests.
  """

  use ExUnit.Case, async: true

  alias Backpex.Preferences.Context

  describe "coerce/1" do
    test "passes a %Context{} through unchanged" do
      ctx = Context.from_mount(%{"backpex_preferences" => %{"global" => %{"theme" => "dark"}}})

      assert Context.coerce(ctx) == ctx
    end

    test "wraps a string-keyed session map via from_mount/1" do
      session = %{"backpex_preferences" => %{"global" => %{"theme" => "dark"}}}

      result = Context.coerce(session)

      assert %Context{} = result
      # The wrapped context exposes the session under the documented field —
      # the value passed through verbatim.
      assert result.session == session
    end

    test "wraps an empty map (degenerate session) without raising" do
      result = Context.coerce(%{})

      assert %Context{} = result
      assert result.session == %{}
    end

    test "raises ArgumentError on an atom-keyed map" do
      assert_raise ArgumentError, ~r/Phoenix session map \(string-keyed\)/, fn ->
        Context.coerce(%{atom_key: 1})
      end
    end

    test "raises ArgumentError on a non-map term" do
      assert_raise ArgumentError, ~r/Phoenix session map/, fn ->
        Context.coerce(:not_a_map)
      end
    end
  end
end
