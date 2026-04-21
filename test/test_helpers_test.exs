defmodule Backpex.TestTest do
  @moduledoc """
  Unit coverage for `Backpex.Test`.

  We exercise the extracted runtime pieces directly:

    * `__resolve_url__/3` — router-based URL derivation and `:url` / `:query`
      overrides.
    * `__same_resource_path__?/2` — path-only equality used by the
      redirect-follow heuristic.
    * `__maybe_follow_redirect__/3` — the retry-once core of
      `live_resource_index/3`, including the same-resource guard.
    * `put_preference/3` — conn-origin writes via the default Session
      adapter.

  A full end-to-end mount test would need a booted Phoenix endpoint and is
  left to integration suites (see `demo/test/...`).
  """

  use ExUnit.Case, async: true

  import Plug.Test

  alias Backpex.Preferences
  alias Backpex.Preferences.Keys

  # --- Fake router modules for __resolve_url__ ------------------------------

  defmodule FakeResourceLive.Index do
    # The LiveView module referenced by the router's :log_module metadata.
    # Only the module name is load-bearing for this helper.
  end

  defmodule FakeResourceLive do
    # The LiveResource module passed to `live_resource_index/3`. The helper
    # concatenates ".Index" to find the actual route.
  end

  defmodule FakeRouter do
    @routes [
      %{
        path: "/admin/posts",
        plug: Phoenix.LiveView.Plug,
        plug_opts: :index,
        metadata: %{log_module: Backpex.TestTest.FakeResourceLive.Index}
      },
      %{
        path: "/admin/posts/new",
        plug: Phoenix.LiveView.Plug,
        plug_opts: :new,
        metadata: %{log_module: Backpex.TestTest.FakeResourceLive.Form}
      },
      %{
        path: "/admin/posts/:backpex_id/show",
        plug: Phoenix.LiveView.Plug,
        plug_opts: :show,
        metadata: %{log_module: Backpex.TestTest.FakeResourceLive.Show}
      }
    ]

    def __routes__, do: @routes
  end

  # Builds a conn whose `:phoenix_router` private is populated — mirrors what
  # Phoenix.ConnTest gives you after a dispatched request.
  defp conn_with_router(router \\ FakeRouter) do
    conn(:get, "/")
    |> Plug.Conn.put_private(:phoenix_router, router)
  end

  # --- __same_resource_path__? ----------------------------------------------

  describe "__same_resource_path__?/2" do
    test "returns true when paths match (ignoring query strings)" do
      assert Backpex.Test.__same_resource_path__?("/admin/posts", "/admin/posts")

      assert Backpex.Test.__same_resource_path__?(
               "/admin/posts",
               "/admin/posts?filters[published][]=published"
             )

      assert Backpex.Test.__same_resource_path__?(
               "/admin/posts?a=1",
               "/admin/posts?b=2"
             )
    end

    test "returns false when paths differ" do
      refute Backpex.Test.__same_resource_path__?("/admin/posts", "/admin/users")
      refute Backpex.Test.__same_resource_path__?("/admin/posts", "/admin/posts/new")
    end
  end

  # --- __maybe_follow_redirect__ --------------------------------------------

  describe "__maybe_follow_redirect__/3" do
    test "passes {:ok, _, _} through unchanged (no redirect, no retry)" do
      result = {:ok, :view, "<html></html>"}

      # If rerun is invoked, the assertion trips.
      assert Backpex.Test.__maybe_follow_redirect__(result, "/admin/posts", fn _to ->
               flunk("rerun should not be called on a successful mount")
             end) == result
    end

    test "follows a same-resource live_redirect exactly once" do
      initial = {:error, {:live_redirect, %{to: "/admin/posts?filters[published][]=published"}}}
      followed = {:ok, :view, "<html>followed</html>"}

      assert Backpex.Test.__maybe_follow_redirect__(initial, "/admin/posts", fn to ->
               assert to == "/admin/posts?filters[published][]=published"
               followed
             end) == followed
    end

    test "bubbles a cross-resource redirect up as-is (no retry)" do
      initial = {:error, {:live_redirect, %{to: "/admin/users"}}}

      result =
        Backpex.Test.__maybe_follow_redirect__(initial, "/admin/posts", fn _to ->
          flunk("must not follow a cross-resource redirect")
        end)

      assert result == initial
    end

    test "passes non-live-redirect errors through unchanged" do
      initial = {:error, :nxdomain}

      assert Backpex.Test.__maybe_follow_redirect__(initial, "/admin/posts", fn _to ->
               flunk("errors other than :live_redirect must not trigger a retry")
             end) == initial
    end
  end

  # --- __resolve_url__ ------------------------------------------------------

  describe "__resolve_url__/3 with a router-derived URL" do
    test "returns the Index path for the resource" do
      assert Backpex.Test.__resolve_url__(conn_with_router(), FakeResourceLive, []) ==
               "/admin/posts"
    end

    test "appends encoded query params from :query (map)" do
      conn = conn_with_router()

      url =
        Backpex.Test.__resolve_url__(conn, FakeResourceLive, query: %{"page" => 2, "sort" => "asc"})

      assert String.starts_with?(url, "/admin/posts?")
      # Plug.Conn.Query doesn't guarantee ordering — assert on parsed form.
      assert "/admin/posts" <> "?" <> qs = url
      assert URI.decode_query(qs) == %{"page" => "2", "sort" => "asc"}
    end

    test "appends encoded query params from :query (keyword)" do
      conn = conn_with_router()

      url = Backpex.Test.__resolve_url__(conn, FakeResourceLive, query: [page: 2])

      assert url == "/admin/posts?page=2"
    end

    test "ignores an empty :query and returns the bare path" do
      conn = conn_with_router()

      assert Backpex.Test.__resolve_url__(conn, FakeResourceLive, query: %{}) == "/admin/posts"
      assert Backpex.Test.__resolve_url__(conn, FakeResourceLive, query: []) == "/admin/posts"
    end
  end

  describe "__resolve_url__/3 with a :url override" do
    test "returns the URL verbatim and does not consult the router" do
      # Deliberately pass a conn with no :phoenix_router — the override should
      # make the router lookup unnecessary.
      conn = conn(:get, "/")

      assert Backpex.Test.__resolve_url__(conn, FakeResourceLive, url: "/custom/path?a=1") ==
               "/custom/path?a=1"
    end

    test "takes precedence over :query" do
      assert Backpex.Test.__resolve_url__(
               conn_with_router(),
               FakeResourceLive,
               url: "/other?existing=1",
               query: %{ignored: true}
             ) == "/other?existing=1"
    end
  end

  describe "__resolve_url__/3 error cases" do
    test "raises when the router is missing and no :url override is given" do
      # A fresh Plug.Test conn has no :phoenix_router.
      conn = conn(:get, "/")

      assert_raise ArgumentError, ~r/could not determine the router/, fn ->
        Backpex.Test.__resolve_url__(conn, FakeResourceLive, [])
      end
    end

    test "raises when the resource has no matching Index route" do
      defmodule EmptyRouter do
        def __routes__, do: []
      end

      conn = conn_with_router(EmptyRouter)

      assert_raise ArgumentError, ~r/could not find an Index route/, fn ->
        Backpex.Test.__resolve_url__(conn, FakeResourceLive, [])
      end
    end
  end

  # --- put_preference -------------------------------------------------------

  describe "put_preference/3" do
    test "seeds a value that Backpex.Preferences.get/3 then reads back" do
      key = Keys.theme()

      conn =
        conn(:get, "/")
        |> Plug.Test.init_test_session(%{})
        |> Backpex.Test.put_preference(key, "dark")

      # The default (no-config) router sends everything to the Session adapter,
      # which serializes through the conn's session store — so reading through
      # the session map that the conn now carries gives back the seeded value.
      session = Plug.Conn.get_session(conn)
      assert Preferences.get(session, key) == "dark"
    end

    test "returns the updated conn (usable for further pipe chaining)" do
      conn =
        conn(:get, "/")
        |> Plug.Test.init_test_session(%{})

      conn2 = Backpex.Test.put_preference(conn, Keys.sidebar_open(), false)

      assert %Plug.Conn{} = conn2
      # The original conn is untouched (Plug.Conn is a struct, not an agent).
      assert Plug.Conn.get_session(conn) == %{}

      assert Plug.Conn.get_session(conn2, Preferences.session_key()) ==
               %{"global" => %{"sidebar_open" => false}}
    end

    test "raises with a useful message when the adapter refuses the write" do
      # Route the theme key to an adapter that refuses every write. Use
      # `Application.put_env` scoped to this test with an `on_exit` cleanup so
      # we don't leak into the rest of the suite.
      on_exit(fn -> Application.delete_env(:backpex, Backpex.Preferences) end)

      Application.put_env(:backpex, Backpex.Preferences, adapters: [{:default, Backpex.TestTest.RefusingAdapter, []}])

      conn =
        conn(:get, "/")
        |> Plug.Test.init_test_session(%{})

      assert_raise ArgumentError, ~r/put_preference\/3 failed/, fn ->
        Backpex.Test.put_preference(conn, Keys.theme(), "dark")
      end
    end
  end

  defmodule RefusingAdapter do
    @behaviour Backpex.Preferences.Adapter

    @impl Backpex.Preferences.Adapter
    def get(_ctx, _key, _opts), do: {:ok, :not_found}

    @impl Backpex.Preferences.Adapter
    def get_map(_ctx, _prefix, _opts), do: {:ok, %{}}

    @impl Backpex.Preferences.Adapter
    def put(_ctx, _key, _value, _opts), do: {:error, :nope}
  end
end
