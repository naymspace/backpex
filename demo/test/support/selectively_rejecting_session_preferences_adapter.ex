defmodule DemoWeb.SelectivelyRejectingSessionPreferencesAdapter do
  @moduledoc false

  @behaviour Backpex.Preferences.Adapter

  alias Backpex.Preferences.Adapter
  alias Backpex.Preferences.Adapters.Session

  @impl Adapter
  defdelegate get(ctx, key, opts), to: Session

  @impl Adapter
  defdelegate get_map(ctx, prefix, opts), to: Session

  @impl Adapter
  defdelegate client_namespace(ctx, opts), to: Session

  @impl Adapter
  def put(_ctx, "global.sidebar_open", _value, _opts), do: {:error, :rejected}
  def put(ctx, key, value, opts), do: Session.put(ctx, key, value, opts)
end
