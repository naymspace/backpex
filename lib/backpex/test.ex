defmodule Backpex.Test do
  @moduledoc """
  Test helpers for host applications that integrate Backpex.

  This module ships with Backpex so downstream apps' ExUnit suites can `import`
  it directly — no copy-pasting, no extra dependency.

  ## `live_resource_index/3` — transparently follow the default-filter redirect

  When a LiveResource has filter presets configured via `:default` on a filter
  config and the current user has no persisted filter state yet,
  `Backpex.LiveResource.Index` mounts, then immediately `push_navigate`s to the
  same path with the default filters applied. Under `Phoenix.LiveViewTest.live/2`
  this surfaces as:

      {:error, {:live_redirect, %{to: to}}} = live(conn, ~p"/admin/posts")

  — forcing every test to re-mount at `to` manually. `live_resource_index/3`
  follows that redirect once and returns the usual `{:ok, view, html}`:

      import Backpex.Test

      {:ok, view, html} = live_resource_index(conn, DemoWeb.PostLive)
      # subsequent assertions on view/html work as if the redirect hadn't happened

  The macro expands into `Phoenix.LiveViewTest.live/2` under the hood, so the
  caller must have `@endpoint` set and `Phoenix.LiveViewTest` imported — the
  same setup `live/2` itself requires. (Phoenix's `ConnCase` already does both.)

  A redirect to a **different** resource is not followed: it bubbles up as the
  original `{:error, ...}` tuple so the test can decide how to handle it. Only
  one hop is ever performed; an infinite redirect would indicate a bug and
  surface as the second hop's tuple.

  ## `put_preference/3` — seed a preference for the next mount

  Lets a test install a preference into a `Plug.Conn`'s session before calling
  `live_resource_index/3`, without routing through the HTTP preferences
  controller:

      conn =
        conn
        |> put_preference(Backpex.Preferences.Keys.filters(DemoWeb.PostLive), %{})

      {:ok, _view, html} = live_resource_index(conn, DemoWeb.PostLive)

  This is convenient for pinning "user has explicitly cleared all filters"
  scenarios and similar persisted-state-on-mount tests.
  """

  alias Backpex.Preferences
  alias Plug.Conn.Query

  @doc """
  Mounts a LiveResource Index view, transparently following the default-filter
  redirect if one is issued on mount.

  See the module doc for the problem this solves and when to reach for it.

  ## Arguments

    * `conn` — a `%Plug.Conn{}`, typically the one injected by `ConnCase`.
    * `resource_mod` — the LiveResource module (e.g. `MyAppWeb.PostLive`), not
      the generated `*.Index` sub-module.
    * `opts` — optional keyword list:
        * `:url` — override the mount URL. Defaults to the Index route derived
          from the router for `resource_mod`. Useful when the resource is
          mounted under multiple paths or when you want to pass query params
          explicitly.
        * `:query` — map or keyword list of query parameters to append to the
          derived URL (merged into the query string). Ignored when `:url` is
          given.

  ## Return

  Whatever `Phoenix.LiveViewTest.live/2` returns on success:

      {:ok, view, html}

  If the initial mount returns `{:error, {:live_redirect, %{to: to}}}` **and**
  `to` points at the same resource's Index path, the macro re-mounts at `to`
  once and returns that call's result. A redirect to a different path surfaces
  as the original `{:error, ...}` tuple.

  ## Example

      import Backpex.Test

      test "index renders with default filters applied", %{conn: conn} do
        {:ok, _view, html} = live_resource_index(conn, DemoWeb.PostLive)
        assert html =~ "Published"
      end
  """
  defmacro live_resource_index(conn, resource_mod, opts \\ []) do
    quote bind_quoted: [conn: conn, resource_mod: resource_mod, opts: opts] do
      url = Backpex.Test.__resolve_url__(conn, resource_mod, opts)
      initial = Phoenix.LiveViewTest.live(conn, url)

      Backpex.Test.__maybe_follow_redirect__(initial, url, fn to ->
        Phoenix.LiveViewTest.live(conn, to)
      end)
    end
  end

  @doc false
  # Runtime piece of live_resource_index/3's redirect-follow logic. Extracted so
  # the behavior is unit-testable without needing a live Phoenix endpoint.
  #
  #   * `initial` is whatever `Phoenix.LiveViewTest.live/2` returned.
  #   * `from` is the URL we originally called `live/2` with.
  #   * `rerun` is a 1-arity function that re-runs `live/2` against a new URL.
  #
  # Follows the redirect exactly once, and only if the target resolves to the
  # same path prefix as `from`. Any other result (success, non-live-redirect
  # error, cross-resource redirect) is returned unchanged.
  def __maybe_follow_redirect__(initial, from, rerun) when is_function(rerun, 1) do
    case initial do
      {:error, {:live_redirect, %{to: to}}} = error ->
        if __same_resource_path__?(from, to) do
          rerun.(to)
        else
          error
        end

      other ->
        other
    end
  end

  @doc """
  Seeds a preference into the `Plug.Conn`'s session, so the next LiveView mount
  reads it as if the user had set it previously.

  Useful for pinning tests that exercise persisted-state branches in
  `Backpex.LiveResource.Index` (e.g. "user has explicitly cleared all
  filters", "user's saved column visibility hides column X").

  Returns the updated conn.

  ## Example

      conn =
        conn
        |> put_preference(Backpex.Preferences.Keys.columns(MyApp.PostLive), %{"title" => false})

      {:ok, _view, html} = live_resource_index(conn, MyApp.PostLive)
      refute html =~ "Title"
  """
  @spec put_preference(Plug.Conn.t(), String.t(), term()) :: Plug.Conn.t()
  def put_preference(%Plug.Conn{} = conn, key, value) when is_binary(key) do
    case Preferences.put(conn, key, value) do
      {:ok, %Plug.Conn{} = updated_conn} ->
        updated_conn

      {:error, reason} ->
        raise ArgumentError,
              "Backpex.Test.put_preference/3 failed for key #{inspect(key)}: #{inspect(reason)}. " <>
                "Make sure the adapter routed to this key accepts writes from a %Plug.Conn{} " <>
                "(the default Session adapter does)."
    end
  end

  @doc false
  # Resolves the Index mount URL for `resource_mod` from the conn's router.
  # Returns the raw path string, optionally with a query string appended.
  def __resolve_url__(%Plug.Conn{} = conn, resource_mod, opts) do
    case Keyword.get(opts, :url) do
      url when is_binary(url) ->
        url

      nil ->
        conn
        |> router_for!()
        |> find_index_path!(resource_mod)
        |> maybe_append_query(Keyword.get(opts, :query))
    end
  end

  @doc false
  # Returns true when `to` (a `live_redirect` target) points at the same
  # resource Index path as `from` — i.e. its path (ignoring query) equals the
  # path component of `from`. The user is free to change the query string; we
  # only care that the redirect stays on the same resource.
  def __same_resource_path__?(from, to) when is_binary(from) and is_binary(to) do
    path(from) == path(to)
  end

  defp path(url) do
    url
    |> String.split("?", parts: 2)
    |> hd()
  end

  defp router_for!(%Plug.Conn{} = conn) do
    conn.private[:phoenix_router] ||
      raise ArgumentError, """
      Backpex.Test could not determine the router for the given conn.

      Make sure the conn has been dispatched at least once (so `:phoenix_router`
      is populated in `conn.private`), or pass an explicit `:url` option to
      live_resource_index/3.
      """
  end

  defp safe_index_module!(resource_mod) do
    Module.safe_concat(resource_mod, Index)
  rescue
    ArgumentError ->
      reraise ArgumentError.exception("""
              Backpex.Test could not resolve #{inspect(resource_mod)}.Index.

              Make sure you passed the top-level LiveResource module (e.g. MyAppWeb.PostLive),
              not a sub-module like *.Index or *.Show, and that the resource is mounted in your
              router.
              """),
              __STACKTRACE__
  end

  defp find_index_path!(router, resource_mod) do
    # `Module.safe_concat/2` refuses to coin a brand new atom at runtime. For
    # the Index module of a live resource that's actually routed, the atom has
    # already been materialized by the router — so a safe concat is correct
    # and cheaper in atom-table pressure than `Module.concat/2`.
    index_module = safe_index_module!(resource_mod)

    route =
      Enum.find(router.__routes__(), fn r ->
        r.metadata[:log_module] == index_module and r.plug_opts == :index
      end)

    case route do
      %{path: path} ->
        path

      nil ->
        raise ArgumentError, """
        Backpex.Test could not find an Index route for #{inspect(resource_mod)} in #{inspect(router)}.

        Make sure the resource is mounted with `live_resources/2` in your router, or pass an
        explicit `:url` option to live_resource_index/3.
        """
    end
  end

  defp maybe_append_query(path, nil), do: path
  defp maybe_append_query(path, query) when query == %{} or query == [], do: path

  defp maybe_append_query(path, query) do
    encoded = query |> normalize_query() |> Query.encode()
    path <> "?" <> encoded
  end

  defp normalize_query(query) when is_list(query), do: Map.new(query)
  defp normalize_query(query) when is_map(query), do: query
end
