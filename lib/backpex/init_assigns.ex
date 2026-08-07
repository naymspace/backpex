defmodule Backpex.InitAssigns do
  @moduledoc """
  Ensures Backpex `assigns` are applied to all LiveViews attaching this hook.

  Must run **after** your app's authentication `on_mount` hook so that
  `socket.assigns` already holds `:current_user` / `:current_scope` (or
  whatever your scope resolver looks for) by the time preferences are
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
    # scope resolvers need. The context also carries the browser's own
    # preference overlay — connect params on a connected mount, the
    # `backpex_prefs` cookie on the dead render — which overrides stored values
    # the browser is known to be ahead of. See `Backpex.Preferences.LiveView`.
    ctx = PreferenceLiveView.mount_context(socket, session)

    socket =
      socket
      |> assign_preferences_manifest(ctx)
      |> assign_current_theme(ctx)
      |> assign_sidebar_open(ctx)
      |> assign_sidebar_section_states(ctx)
      |> attach_current_url_hook()

    {:cont, socket}
  end

  # The browser cannot know which adapter namespace it is talking to; the
  # server can. Each adapter route receives an opaque token for the namespace it
  # actually uses. Layouts hand this manifest to the browser so session-backed values can
  # survive an application-scope change without carrying tenant-scoped values
  # with them. `nil` disables the client overlay when tokens cannot be signed.
  defp assign_preferences_manifest(socket, ctx) do
    assign(socket, :preferences_manifest, PreferenceLiveView.client_manifest(ctx, socket.endpoint))
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

  # `sidebar_section/1` renders `data-section-open={to_string(@open)}`, which
  # raises on a map. Drop individual sections whose stored state is not a
  # boolean rather than the whole map — one bad section should not reset the
  # rest — and let the component's default (open) apply to those.
  defp assign_sidebar_section_states(socket, ctx) do
    section_states =
      ctx
      |> Preferences.get_map(Keys.sidebar_section_prefix())
      |> Map.filter(fn {_id, open} -> is_boolean(open) end)

    assign(socket, :sidebar_section_states, section_states)
  end

  defp attach_current_url_hook(socket) do
    attach_hook(socket, :current_url, :handle_params, fn
      _params, url, socket -> {:cont, assign(socket, current_url: url)}
    end)
  end
end
