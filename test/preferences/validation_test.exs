defmodule Backpex.Preferences.ValidationTest do
  @moduledoc """
  Exercises the opt-in `validate_keys` config on the `Backpex.Preferences`
  dispatcher. Each describe block mutates the
  `:backpex, Backpex.Preferences` env, so the whole file runs serially.
  """

  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Backpex.Preferences
  alias Backpex.Preferences.Context
  alias Backpex.Preferences.Keys

  setup do
    prior = Application.get_env(:backpex, Backpex.Preferences)

    on_exit(fn ->
      case prior do
        nil -> Application.delete_env(:backpex, Backpex.Preferences)
        value -> Application.put_env(:backpex, Backpex.Preferences, value)
      end
    end)

    :ok
  end

  describe "default config — no :validate_keys" do
    test "get/3 does not log on unknown keys" do
      Application.delete_env(:backpex, Backpex.Preferences)

      log =
        capture_log(fn ->
          assert Preferences.get(%{}, "globl.theme", default: "light") == "light"
        end)

      refute log =~ "unknown preference key"
    end

    test "get/3 does not raise on unknown keys" do
      Application.delete_env(:backpex, Backpex.Preferences)

      # Sanity check: validation is fully off — a wildly malformed key still
      # just routes through the default Session adapter and falls back.
      assert Preferences.get(%{}, "", default: "fallback") == "fallback"
    end
  end

  describe "validate_keys: :log" do
    setup do
      Application.put_env(:backpex, Backpex.Preferences, validate_keys: :log)
      :ok
    end

    test "logs a warning on unknown keys and still dispatches get/3" do
      log =
        capture_log(fn ->
          # Reads still succeed — validation is loud but non-blocking.
          assert Preferences.get(%{}, "globl.theme", default: "light") == "light"
        end)

      assert log =~ "unknown preference key"
      assert log =~ "globl.theme"
      assert log =~ ":unknown_prefix"
    end

    test "logs a warning on unknown keys for fetch/3 and still returns :error" do
      log =
        capture_log(fn ->
          assert Preferences.fetch(%{}, "nope.foo") == :error
        end)

      assert log =~ "unknown preference key"
      assert log =~ "nope.foo"
    end

    test "logs only once per call — no double-log on success path" do
      log =
        capture_log(fn ->
          assert Preferences.get(%{}, "global.theme", default: "light") == "light"
        end)

      refute log =~ "unknown preference key"
    end

    test "logs a warning on unknown prefix for get_map/3" do
      log =
        capture_log(fn ->
          assert Preferences.get_map(%{}, "globl") == %{}
        end)

      assert log =~ "unknown preference key"
      assert log =~ "globl"
    end

    test "logs a warning on unknown keys in put_batch/3 and still proceeds" do
      # :controller source so the Session adapter emits put_session effects
      # rather than refusing with :requires_http.
      ctx = %{Context.from_mount(%{}) | source: :controller}

      {result, log} =
        with_log(fn ->
          Preferences.put_batch(ctx, [
            {Keys.theme(), "dark"},
            {"globl.unknown", "value"}
          ])
        end)

      # Validation is loud but non-blocking — both writes go through.
      assert {:ok, effects} = result
      assert is_list(effects)
      assert log =~ "unknown preference key"
      assert log =~ "globl.unknown"
      assert log =~ ":put_batch"
    end
  end

  describe "validate_keys: true" do
    setup do
      Application.put_env(:backpex, Backpex.Preferences, validate_keys: true)
      :ok
    end

    test "raises ArgumentError on unknown keys in get/3" do
      assert_raise ArgumentError, ~r/invalid preference key/, fn ->
        Preferences.get(%{}, "globl.theme")
      end
    end

    test "raises ArgumentError on unknown keys in fetch/3" do
      assert_raise ArgumentError, ~r/invalid preference key/, fn ->
        Preferences.fetch(%{}, "globl.theme")
      end
    end

    test "raises ArgumentError on unknown prefix in get_map/3" do
      assert_raise ArgumentError, ~r/invalid preference key/, fn ->
        Preferences.get_map(%{}, "nope")
      end
    end

    test "known keys pass through untouched" do
      # Sanity: the :raise mode must not break the happy path.
      assert Preferences.get(%{}, "global.theme", default: "light") == "light"
      assert Preferences.fetch(%{}, "global.theme") == :error
      assert Preferences.get_map(%{}, "global") == %{}
    end

    test "raises ArgumentError on unknown keys in put_batch/3" do
      ctx = %{Context.from_mount(%{}) | source: :controller}

      assert_raise ArgumentError, ~r/invalid preference key/, fn ->
        Preferences.put_batch(ctx, [{"globl.unknown", "value"}])
      end
    end

    test "put_batch/3 raises on the first unknown key encountered" do
      # The reduce_while loop validates each entry left-to-right; the first
      # unknown key short-circuits with a raise. Entries before it may have
      # been dispatched already (the eager-write caveat in the moduledoc).
      ctx = %{Context.from_mount(%{}) | source: :controller}

      assert_raise ArgumentError, ~r/globl\.unknown/, fn ->
        Preferences.put_batch(ctx, [
          {Keys.theme(), "dark"},
          {"globl.unknown", "value"}
        ])
      end
    end
  end

  describe "validate_keys: false" do
    setup do
      Application.put_env(:backpex, Backpex.Preferences, validate_keys: false)
      :ok
    end

    test "behaves like no config — no log, no raise" do
      log =
        capture_log(fn ->
          assert Preferences.get(%{}, "globl.theme", default: "light") == "light"
        end)

      refute log =~ "unknown preference key"
    end

    test "put_batch/3 proceeds silently on unknown keys" do
      ctx = %{Context.from_mount(%{}) | source: :controller}

      log =
        capture_log(fn ->
          assert {:ok, _effects} =
                   Preferences.put_batch(ctx, [{"globl.unknown", "value"}])
        end)

      refute log =~ "unknown preference key"
    end
  end
end
