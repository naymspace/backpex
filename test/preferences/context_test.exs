defmodule Backpex.Preferences.ContextTest do
  @moduledoc """
  Runs the `Backpex.Preferences.Context` doctests and adds targeted coverage
  for `coerce/1`.

  The doctests pin `put_client/2` at the client trust boundary, where every
  key and value is browser-written and therefore untrusted: a key with an
  unknown prefix is dropped, a wrong-typed value for a built-in key is
  dropped, and a well-shaped value for that same key survives. The last case
  is what keeps the other two honest — a gate that rejected everything would
  satisfy the rejection examples on its own.

  Each clause of `coerce/1` has a distinct behavior that callers rely on
  (pass-through, wrap, raise on atom-keyed maps, raise on non-map terms),
  and the branches were previously only exercised indirectly through
  higher-level tests.
  """

  use ExUnit.Case, async: true

  alias Backpex.Preferences.Context

  doctest Context

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
