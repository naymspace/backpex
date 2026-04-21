defmodule Backpex.InitAssigns do
  @moduledoc """
  Ensures Backpex `assigns` are applied to all LiveViews attaching this hook.
  """

  use BackpexWeb, :html
  import Phoenix.LiveView

  alias Backpex.Preferences
  alias Backpex.Preferences.Keys

  def on_mount(:default, _params, session, socket) do
    socket =
      socket
      |> assign_current_theme(session)
      |> assign_sidebar_open(session)
      |> assign_sidebar_section_states(session)
      |> attach_current_url_hook()

    {:cont, socket}
  end

  defp assign_current_theme(socket, session) do
    theme = Preferences.get(session, Keys.theme())
    assign(socket, :current_theme, theme)
  end

  defp assign_sidebar_open(socket, session) do
    sidebar_open = Preferences.get(session, Keys.sidebar_open(), default: true)
    assign(socket, :sidebar_open, sidebar_open)
  end

  defp assign_sidebar_section_states(socket, session) do
    section_states = Preferences.get_map(session, Keys.sidebar_section_prefix())
    assign(socket, :sidebar_section_states, section_states)
  end

  defp attach_current_url_hook(socket) do
    attach_hook(socket, :current_url, :handle_params, fn
      _params, url, socket -> {:cont, assign(socket, current_url: url)}
    end)
  end
end
