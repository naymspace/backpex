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
  alias Backpex.Preferences.Keys
  alias Backpex.Preferences.LiveView, as: PreferenceLiveView

  def on_mount(:default, _params, session, socket) do
    # Build the Context once so every read sees the same session + assigns
    # snapshot. `socket.assigns` already contains whatever the app's auth hook
    # put there (current_user, current_scope, ...), which is exactly what
    # identity resolvers need. The context also carries the browser's own
    # preference overlay — connect params on a connected mount, the
    # `backpex_prefs` cookie on the dead render — which overrides stored values
    # the browser is known to be ahead of. See `Backpex.Preferences.LiveView`.
    ctx = PreferenceLiveView.mount_context(socket, session)

    socket =
      socket
      |> assign_preferences_identity(ctx)
      |> assign_current_theme(ctx)
      |> assign_sidebar_open(ctx)
      |> assign_sidebar_section_states(ctx)
      |> attach_current_url_hook()

    {:cont, socket}
  end

  # The browser cannot know who it is talking to; the server can. Hand it an
  # opaque fingerprint of the current preference identity so it can stamp the
  # unacknowledged writes it holds in `backpex_prefs` and drop them again once
  # the identity changes — otherwise the write user A left in flight when they
  # logged out would be rendered for, and replayed by, user B. Layouts pass this
  # to `Backpex.HTML.Layout.app_shell/1`; `nil` (no endpoint secret, or a session
  # with no CSRF token yet) turns the pending cookie off entirely.
  defp assign_preferences_identity(socket, ctx) do
    assign(socket, :preferences_identity, PreferenceLiveView.identity_fingerprint(ctx, socket.endpoint))
  end

  defp assign_current_theme(socket, ctx) do
    theme = Preferences.get(ctx, Keys.theme())
    assign(socket, :current_theme, theme)
  end

  # The write path refuses a non-boolean here, but a store can still hold one
  # from an earlier Backpex version or a third-party adapter, and `app_shell/1`
  # renders `inert={not @sidebar_open}` — which raises on anything else. Falling
  # back to the default keeps a bad stored value from 500ing every page.
  defp assign_sidebar_open(socket, ctx) do
    sidebar_open =
      case Preferences.get(ctx, Keys.sidebar_open(), default: true) do
        open when is_boolean(open) -> open
        _other -> true
      end

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
