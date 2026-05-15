defmodule Backpex.Test.UnidentifiedPreferencesAdapter do
  @moduledoc """
  Test-only `Backpex.Preferences.Adapter` whose `put/4` always returns
  `{:error, :unidentified}`. Reads succeed as "not found."

  Used to exercise the controller's anonymous-visitor carve-out, where a
  single-write `:unidentified` is treated as a 200 no-op instead of a 422.
  """

  @behaviour Backpex.Preferences.Adapter

  alias Backpex.Preferences.Adapter

  @impl Adapter
  def get(_ctx, _key, _opts), do: {:ok, :not_found}

  @impl Adapter
  def get_map(_ctx, _prefix, _opts), do: {:ok, %{}}

  @impl Adapter
  def put(_ctx, _key, _value, _opts), do: {:error, :unidentified}
end
