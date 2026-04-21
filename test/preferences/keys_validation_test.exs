defmodule Backpex.Preferences.KeysValidationTest do
  @moduledoc """
  Paranoid self-check: every public helper in `Backpex.Preferences.Keys`
  must emit a key that passes `Backpex.Preferences.Key.validate/1`.

  The `@after_compile` callback on `Keys` already exercises every 0-arity
  helper at compile time. This module covers 1-arity helpers (which take
  a LiveResource module) by invoking each with a dummy module and piping
  the result through `Key.validate/1`. Any future refactor that breaks
  the emitted encoding will fail here instead of silently producing keys
  that the dispatcher rejects.
  """

  use ExUnit.Case, async: true

  alias Backpex.Preferences.Key
  alias Backpex.Preferences.Keys

  @dummy_module MyApp.DummyLive

  test "every 0-arity helper emits a key that validates" do
    for {name, 0} <- Keys.__info__(:functions),
        name not in [:__info__, :module_info] do
      key = apply(Keys, name, [])

      assert Key.validate(key) == :ok,
             "Keys.#{name}/0 emitted #{inspect(key)} which failed validation"
    end
  end

  test "every 1-arity helper emits a key that validates" do
    # 1-arity helpers in `Keys` take a LiveResource module. Feeding a
    # dummy module is enough to exercise the encoding — we're checking
    # the shape of the emitted key, not any module-specific behavior.
    for {name, 1} <- Keys.__info__(:functions),
        name not in [:__info__, :module_info] do
      key = apply(Keys, name, [@dummy_module])

      assert Key.validate(key) == :ok,
             "Keys.#{name}/1 emitted #{inspect(key)} for dummy module; failed validation"
    end
  end
end
