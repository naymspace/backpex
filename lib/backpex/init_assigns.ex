defmodule Backpex.InitAssigns do
  @moduledoc """
  Ensures Backpex `assigns` are applied to all LiveViews attaching this hook.
  """

  use BackpexWeb, :html
  import Phoenix.LiveView

  def on_mount(:default, _params, _session, socket) do
    socket =
      socket
      |> attach_current_url_hook()

    {:cont, socket}
  end

  defp attach_current_url_hook(socket) do
    attach_hook(socket, :current_url, :handle_params, fn
      _params, url, socket -> {:cont, assign(socket, current_url: url)}
    end)
  end
end
