defmodule Backpex.Preferences.Adapters.Session do
  @moduledoc """
  Session-backed `Backpex.Preferences` adapter.

  Stores all preferences as a single nested map under one Phoenix session key
  (`"backpex_preferences"`). Exact storage characteristics depend on the host
  app's `Plug.Session` backend (cookie, ETS, Redis, ...). The default cookie
  store has a ~4KB limit; prefer a database-backed adapter when you expect
  bulky per-user data.

  Reference implementation for the `Backpex.Preferences.Adapter` behavior — a
  reasonable template when writing your own adapter.

  ## Size limit

  With the default `:cookie` session store the whole session — Backpex's
  preferences *plus* everything the host app keeps in it, such as
  `phx.gen.auth`'s user token — travels in one `Set-Cookie` header, and
  `Plug.Conn` refuses to send a header longer than 4096 bytes: it raises
  `Plug.Conn.CookieOverflowError`, the request 500s, and the write is lost.
  `put/4` therefore estimates the size of that header and refuses a write that
  would breach the budget with `{:error, :too_large}`, leaving the stored value
  untouched; `Backpex.PreferencesController` turns that into a `422` so the
  browser can stop carrying the write. A warning is logged well before the
  ceiling.

  ### Options

    * `:max_bytes` — the budget for the session cookie's whole `Set-Cookie`
      header (name, signed value and attributes), in bytes (default: `4096`,
      `Plug.Conn`'s limit). Use `:infinity` for a server-side session store
      (ETS, Redis, ...), which has no such cap:

          config :backpex, Backpex.Preferences,
            adapters: [
              {:default, Backpex.Preferences.Adapters.Session, max_bytes: :infinity}
            ]

  The estimate covers the whole session, not just Backpex's subtree. It counts
  the ~4/3 growth of Base64 and reserves 256 bytes for the rest of the header:
  the signature (and encryption, with `:encryption_salt`), the cookie name and
  the attributes `Plug.Session` adds (`path`, `HttpOnly`, `SameSite`,
  `secure`, `max-age`/`expires`, `domain`). The adapter cannot see the
  `Plug.Session` options, so this is deliberately approximate: it is a budget
  check, not an exact reproduction of the store's encoding. If the session
  options are unusually long (a long `:key` or `:domain`, `:extra`
  attributes), lower `:max_bytes` accordingly. Prefer a database-backed
  adapter over raising `:max_bytes` when per-user data genuinely does not fit.

  ## Write-path limitations

  `put/4` returns `{:error, :requires_http}` for any source other than
  `:controller`. `Plug.Session` cannot write to the Phoenix session outside
  an HTTP request cycle. The dispatcher handles this by falling back to
  `push_event/3`, which round-trips the write through the browser and the
  preferences controller.

  ## `nil` values

  `get/3` maps a stored `nil` to `{:ok, :not_found}`. Store a tagged value such
  as `%{"value" => nil}` if application code must distinguish an explicit nil
  from an absent preference.
  """

  @behaviour Backpex.Preferences.Adapter

  alias Backpex.Preferences.Adapter
  alias Backpex.Preferences.Context
  alias Backpex.Preferences.Key

  require Logger

  @session_key "backpex_preferences"

  @doc "Returns the Phoenix session key used to store the preferences tree."
  def session_key, do: @session_key

  @impl Adapter
  def get(%Context{session: session}, key, _opts) do
    path = Key.parse(key)
    value = session |> root() |> get_in(path)

    case value do
      nil -> {:ok, :not_found}
      value -> {:ok, value}
    end
  end

  @impl Adapter
  def client_namespace(_ctx, _opts), do: {:ok, {:session, @session_key}}

  @impl Adapter
  def get_map(%Context{session: session}, prefix, _opts) do
    path = Key.parse(prefix)
    value = get_in(root(session), path)

    case value do
      nil -> {:ok, %{}}
      map when is_map(map) -> {:ok, map}
      _other -> {:ok, %{}}
    end
  end

  # `Plug.Conn`'s ceiling: 4096 bytes for the whole `Set-Cookie` header. Warn
  # at 75% of the budget so there is room to react before writes start being
  # refused.
  @default_max_bytes 4096
  @warn_ratio 0.75

  # `Plug.Session.COOKIE` term-encodes the session and Base64-encodes it, which
  # grows the payload by 4/3. Everything else in the header is a fixed tail:
  #
  #   * the signature: `"SFMyNTY."` plus a `.`-separated Base64'd HMAC adds 52
  #     bytes; `:encryption_salt` adds about 6 more;
  #   * the cookie name and attributes `Plug.Session` passes on: `key=`,
  #     `; path=/`, `; HttpOnly`, `; SameSite=Lax`, and when configured
  #     `; secure`, `; expires=...; max-age=...` and `; domain=...`. With a
  #     15 character key and a 17 character domain these come to 138 bytes.
  #
  # The adapter cannot see the `Plug.Session` options (they live in the
  # plug's `before_send` closure), so it reserves 256 bytes for this tail: the
  # case above plus ~60 bytes for longer keys and domains. An over-estimate is
  # the safe direction for a budget check.
  @cookie_overhead 256

  @impl Adapter
  def put(%Context{source: :controller, session: session}, key, value, opts) do
    path = Key.parse(key)
    updated = session |> root() |> deep_put(path, value)
    max_bytes = Keyword.get(opts, :max_bytes, @default_max_bytes)

    # Measure the whole session the way the store will write it, not just
    # Backpex's subtree: the budget is shared with whatever the host app keeps
    # in the session (auth tokens, flash, ...), and a subtree-only measurement
    # cannot see how much of it is already spoken for.
    size = session |> Map.put(@session_key, updated) |> encoded_size()

    cond do
      max_bytes == :infinity ->
        {:ok, {:put_session, @session_key, updated}}

      size > max_bytes ->
        Logger.warning(
          "Backpex.Preferences: refusing the write to #{inspect(key)}: the session cookie would encode to " <>
            "~#{size} bytes, over the #{max_bytes} byte budget. The cookie session store cannot hold " <>
            "it: sending it would raise CookieOverflowError and lose the write. " <>
            "Route bulky prefixes to a database-backed preferences adapter, or set `max_bytes: " <>
            ":infinity` if this app uses a server-side session store."
        )

        {:error, :too_large}

      size > max_bytes * @warn_ratio ->
        Logger.warning(
          "Backpex.Preferences: the session cookie encodes to ~#{size} bytes, approaching the " <>
            "#{max_bytes} byte budget. Writes will be refused once it is exceeded. Consider routing " <>
            "bulky prefixes to a database-backed preferences adapter."
        )

        {:ok, {:put_session, @session_key, updated}}

      true ->
        {:ok, {:put_session, @session_key, updated}}
    end
  end

  def put(%Context{source: source}, _key, _value, _opts) when source in [:mount, :server] do
    {:error, :requires_http}
  end

  defp encoded_size(session) do
    raw = session |> :erlang.term_to_binary() |> byte_size()
    ceil(raw * 4 / 3) + @cookie_overhead
  end

  # The session key is expected to hold a map, but a misbehaving host app (or
  # a session rewrite by another plug) can stomp on it with a non-map. Coerce
  # any non-map value to `%{}` here so `get_in/2` upstream can't crash on a
  # binary/number/etc.
  defp root(session) when is_map(session) do
    case Map.get(session, @session_key) do
      map when is_map(map) -> map
      _other -> %{}
    end
  end

  defp root(_other), do: %{}

  defp deep_put(map, path, value), do: Adapter.deep_put(map, path, value)
end
