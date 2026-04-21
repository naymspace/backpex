defmodule Backpex.Test.RejectingPreferencesAdapter do
  @moduledoc """
  Test-only `Backpex.Preferences.Adapter` whose `put/4` always returns
  `{:error, :rejected}`. Reads succeed as "not found."

  Used to exercise the controller's error path and the dispatcher's
  short-circuit semantics without having to wire a DB/stubbed adapter.
  """

  @behaviour Backpex.Preferences.Adapter

  @impl Backpex.Preferences.Adapter
  def get(_ctx, _key, _opts), do: {:ok, :not_found}

  @impl Backpex.Preferences.Adapter
  def get_map(_ctx, _prefix, _opts), do: {:ok, %{}}

  @impl Backpex.Preferences.Adapter
  def put(_ctx, _key, _value, _opts), do: {:error, :rejected}
end
