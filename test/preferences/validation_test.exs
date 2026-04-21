defmodule Backpex.Preferences.ValidationTest do
  @moduledoc """
  Exercises the opt-in `validate_keys` config on the `Backpex.Preferences`
  dispatcher. Each describe block mutates the
  `:backpex, Backpex.Preferences` env, so the whole file runs serially.
  """

  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Backpex.Preferences

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
  end
end
