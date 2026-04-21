defmodule Backpex.InitAssigns do
  @moduledoc """
  Ensures Backpex `assigns` are applied to all LiveViews attaching this hook.

  Must run **after** your app's authentication `on_mount` hook so that
  `socket.assigns` already holds `:current_user` / `:current_scope` (or
  whatever your identity resolver looks for) by the time preferences are
  read. See `guides/live_resource/user-preferences.md` for the full ordering
  contract.
  """

  use BackpexWeb, :html
  import Phoenix.LiveView

  alias Backpex.Preferences
  alias Backpex.Preferences.Context
  alias Backpex.Preferences.Keys

  def on_mount(:default, _params, session, socket) do
    # Build the Context once so every read sees the same session + assigns
    # snapshot. `socket.assigns` already contains whatever the app's auth hook
    # put there (current_user, current_scope, ...), which is exactly what
    # identity resolvers need.
    ctx = Context.from_mount(session, socket.assigns)

    socket =
      socket
      |> assign_current_theme(ctx)
      |> assign_sidebar_open(ctx)
      |> assign_sidebar_section_states(ctx)
      |> attach_current_url_hook()

    {:cont, socket}
  end

  defp assign_current_theme(socket, ctx) do
    theme = Preferences.get(ctx, Keys.theme())
    assign(socket, :current_theme, theme)
  end

  defp assign_sidebar_open(socket, ctx) do
    sidebar_open = Preferences.get(ctx, Keys.sidebar_open(), default: true)
    assign(socket, :sidebar_open, sidebar_open)
  end

  defp assign_sidebar_section_states(socket, ctx) do
    section_states = Preferences.get_map(ctx, Keys.sidebar_section_prefix())
    assign(socket, :sidebar_section_states, section_states)
  end

  defp attach_current_url_hook(socket) do
    attach_hook(socket, :current_url, :handle_params, fn
      _params, url, socket -> {:cont, assign(socket, current_url: url)}
    end)
  end
end
