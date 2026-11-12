defmodule Backpex.Preferences.Adapters.SessionTest do
  use ExUnit.Case, async: true

  alias Backpex.Preferences.Adapters.Session
  alias Backpex.Preferences.Context
  alias Backpex.Preferences.Keys
  alias Plug.Session.COOKIE

  describe "client_namespace/2" do
    test "uses the Phoenix session namespace independently of application scope" do
      first = %Context{session: %{}, scope: %{user_id: 7, tenant_id: 70}}
      second = %Context{session: %{}, scope: %{user_id: 7, tenant_id: 71}}

      assert Session.client_namespace(first, []) == {:ok, {:session, "backpex_preferences"}}
      assert Session.client_namespace(second, []) == Session.client_namespace(first, [])
    end
  end

  describe "get/3" do
    test "returns {:ok, value} when the path is populated" do
      ctx = Context.from_mount(%{"backpex_preferences" => %{"global" => %{"theme" => "dark"}}})
      assert Session.get(ctx, Keys.theme(), []) == {:ok, "dark"}
    end

    test "returns {:ok, :not_found} when the path is missing" do
      ctx = Context.from_mount(%{})
      assert Session.get(ctx, Keys.theme(), []) == {:ok, :not_found}
    end

    test "returns {:ok, :not_found} when an intermediate segment is missing" do
      ctx = Context.from_mount(%{"backpex_preferences" => %{"global" => %{}}})
      assert Session.get(ctx, Keys.theme(), []) == {:ok, :not_found}
    end

    test "handles colon-form keys without dot-collision" do
      ctx =
        Context.from_mount(%{
          "backpex_preferences" => %{
            "resource" => %{"MyApp.MyLive" => %{"columns" => %{"name" => true}}}
          }
        })

      assert Session.get(ctx, Keys.columns(MyApp.MyLive), []) == {:ok, %{"name" => true}}
    end
  end

  describe "get_map/3" do
    test "returns the nested map at the prefix" do
      ctx =
        Context.from_mount(%{
          "backpex_preferences" => %{"global" => %{"sidebar_section" => %{"blog" => true}}}
        })

      assert Session.get_map(ctx, Keys.sidebar_section_prefix(), []) == {:ok, %{"blog" => true}}
    end

    test "returns {:ok, %{}} when the prefix is absent" do
      ctx = Context.from_mount(%{})
      assert Session.get_map(ctx, Keys.sidebar_section_prefix(), []) == {:ok, %{}}
    end

    test "returns {:ok, %{}} when the value at the prefix is not a map" do
      ctx = Context.from_mount(%{"backpex_preferences" => %{"global" => %{"theme" => "dark"}}})
      assert Session.get_map(ctx, Keys.theme(), []) == {:ok, %{}}
    end
  end

  describe "put/4" do
    test "returns a :put_session effect that merges into the existing session tree" do
      ctx =
        %{Context.from_mount(%{"backpex_preferences" => %{"global" => %{"theme" => "light"}}}) | source: :controller}

      assert {:ok, {:put_session, "backpex_preferences", merged}} =
               Session.put(ctx, Keys.sidebar_open(), true, [])

      assert merged == %{"global" => %{"theme" => "light", "sidebar_open" => true}}
    end

    test "returns {:error, :requires_http} for mount/server sources" do
      ctx = Context.from_mount(%{})
      assert Session.put(ctx, Keys.theme(), "dark", []) == {:error, :requires_http}

      ctx = Context.from_socket(%{}, %{})
      assert Session.put(ctx, Keys.theme(), "dark", []) == {:error, :requires_http}
    end
  end

  describe "put/4 size budget" do
    defp controller_ctx(session), do: %{Context.from_mount(session) | source: :controller}

    test "refuses a write that would push the encoded session past :max_bytes" do
      ctx = controller_ctx(%{})

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert Session.put(ctx, Keys.theme(), String.duplicate("x", 5_000), []) == {:error, :too_large}
        end)

      assert log =~ "refusing the write"
      assert log =~ "too_large" or log =~ "budget"
    end

    test "counts the host app's own session data against the budget" do
      # Backpex's subtree is small; the host app's session is what fills the
      # cookie. A subtree-only measurement would miss this entirely.
      ctx = controller_ctx(%{"user_token" => String.duplicate("t", 3_500)})

      assert ExUnit.CaptureLog.with_log(fn -> Session.put(ctx, Keys.theme(), "dark", []) end) |> elem(0) ==
               {:error, :too_large}
    end

    test "leaves the stored value untouched when it refuses" do
      stored = %{"global" => %{"theme" => "light"}}
      ctx = controller_ctx(%{"backpex_preferences" => stored})

      ExUnit.CaptureLog.capture_log(fn ->
        assert Session.put(ctx, Keys.theme(), String.duplicate("x", 5_000), []) == {:error, :too_large}
      end)

      assert Session.get(ctx, Keys.theme(), []) == {:ok, "light"}
    end

    test "warns before the ceiling rather than at it" do
      ctx = controller_ctx(%{"user_token" => String.duplicate("t", 2_400)})

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert {:ok, {:put_session, _key, _map}} = Session.put(ctx, Keys.theme(), "dark", [])
        end)

      assert log =~ "approaching"
    end

    test "accepts any size with max_bytes: :infinity" do
      ctx = controller_ctx(%{})
      big = String.duplicate("x", 50_000)

      assert {:ok, {:put_session, _key, map}} = Session.put(ctx, Keys.theme(), big, max_bytes: :infinity)
      assert map == %{"global" => %{"theme" => big}}
    end

    test "honors a custom :max_bytes" do
      ctx = controller_ctx(%{})

      assert ExUnit.CaptureLog.with_log(fn -> Session.put(ctx, Keys.theme(), "dark", max_bytes: 16) end)
             |> elem(0) == {:error, :too_large}
    end
  end

  describe "put/4 size budget against the real cookie store" do
    # What a `phx.gen.auth` app keeps in the session next to Backpex's subtree.
    @host_session %{
      "_csrf_token" => String.duplicate("c", 24),
      "user_token" => :binary.copy(<<0xAB>>, 32)
    }

    @secret_key_base String.duplicate("s", 64)
    @sixty_days 60 * 24 * 60 * 60

    # Production-like `Plug.Session` options: a typical endpoint key plus the
    # attributes that lengthen the `Set-Cookie` header.
    @cookie_options [
      [key: "_my_app_web_key", signing_salt: "signing1", same_site: "Lax", secure: true, max_age: @sixty_days],
      [
        key: "_my_app_web_key",
        signing_salt: "signing1",
        encryption_salt: "encrypt1",
        same_site: "Lax",
        secure: true,
        max_age: @sixty_days
      ],
      [
        key: "_my_app_web_key",
        signing_salt: "signing1",
        same_site: "Lax",
        secure: true,
        max_age: @sixty_days,
        domain: "admin.example.com"
      ]
    ]

    test "the largest accepted write still fits in the Set-Cookie header Plug sends" do
      ctx = %{Context.from_mount(@host_session) | source: :controller}
      {:put_session, key, value} = largest_accepted_write(ctx)
      session = Map.put(@host_session, key, value)

      for opts <- @cookie_options do
        header = set_cookie_header(session, opts)

        assert byte_size(header) <= 4096,
               "#{byte_size(header)} byte Set-Cookie header with #{inspect(Keyword.delete(opts, :signing_salt))}"
      end
    end

    defp largest_accepted_write(ctx) do
      ExUnit.CaptureLog.with_log(fn -> largest_accepted_write(ctx, 0, 4096, nil) end) |> elem(0)
    end

    # Binary search for the longest value `put/4` still accepts.
    defp largest_accepted_write(_ctx, low, high, best) when low > high, do: best

    defp largest_accepted_write(ctx, low, high, best) do
      size = div(low + high, 2)

      case Session.put(ctx, Keys.theme(), String.duplicate("x", size), []) do
        {:ok, effect} -> largest_accepted_write(ctx, size + 1, high, effect)
        {:error, :too_large} -> largest_accepted_write(ctx, low, size - 1, best)
      end
    end

    defp set_cookie_header(session, opts) do
      store_opts = opts |> Keyword.take([:signing_salt, :encryption_salt]) |> COOKIE.init()
      value = COOKIE.put(%Plug.Conn{secret_key_base: @secret_key_base}, nil, session, store_opts)
      cookie_opts = opts |> Keyword.take([:same_site, :secure, :max_age, :domain]) |> Map.new()

      Plug.Conn.Cookies.encode(opts[:key], Map.put(cookie_opts, :value, value))
    end
  end
end
