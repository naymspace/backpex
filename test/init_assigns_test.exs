defmodule Backpex.InitAssignsTest do
  use ExUnit.Case, async: false

  alias Backpex.InitAssigns
  alias Backpex.Preferences.Adapter
  alias Phoenix.LiveView.Lifecycle
  alias Phoenix.LiveView.Socket

  # --- test-only adapter --------------------------------------------------

  defmodule StubAdapter do
    @moduledoc false
    # Returns fixed per-key values regardless of the context. Configure via
    # application env; the `fetch/1` and `fetch_map/1` functions look the key
    # up in a lookup map set by the test.
    @behaviour Adapter

    @table_env_key :backpex_init_assigns_test_stub_adapter

    def set(values) when is_map(values) do
      Application.put_env(:backpex, @table_env_key, values)
    end

    def clear, do: Application.delete_env(:backpex, @table_env_key)

    defp values, do: Application.get_env(:backpex, @table_env_key, %{})

    @impl Adapter
    def get(_ctx, key, _opts) do
      case Map.fetch(values(), key) do
        {:ok, value} -> {:ok, value}
        :error -> {:ok, :not_found}
      end
    end

    @impl Adapter
    def get_map(_ctx, prefix, _opts) do
      map =
        values()
        |> Enum.flat_map(fn {k, v} ->
          case maybe_strip(k, prefix <> ".") do
            nil -> []
            rest -> [{rest, v}]
          end
        end)
        |> Map.new()

      {:ok, map}
    end

    @impl Adapter
    def put(_ctx, _key, _value, _opts), do: {:ok, [:noop]}

    defp maybe_strip(key, prefix) do
      case String.split(key, prefix, parts: 2) do
        ["", rest] -> rest
        _other -> nil
      end
    end
  end

  # --- setup --------------------------------------------------------------

  setup do
    on_exit(fn ->
      StubAdapter.clear()
      Application.delete_env(:backpex, Backpex.Preferences)
    end)

    :ok
  end

  # --- helpers ------------------------------------------------------------

  # Builds a socket compatible with `Phoenix.LiveView.attach_hook/4`.
  #
  # `attach_hook(..., :handle_params, ...)` refuses a socket with `router: nil`,
  # and both `attach_hook` and `assign/3` touch `socket.private` — so the
  # private map must carry a `:lifecycle` struct and a `:live_temp` map.
  defp build_socket do
    %Socket{
      endpoint: __MODULE__.Endpoint,
      router: __MODULE__.Router,
      assigns: %{__changed__: %{}},
      private: %{
        connect_info: %{},
        lifecycle: %Lifecycle{},
        live_temp: %{}
      }
    }
  end

  defp mount(session, socket \\ build_socket()) do
    {:cont, socket} = InitAssigns.on_mount(:default, %{}, session, socket)
    socket
  end

  # --- tests --------------------------------------------------------------

  describe "on_mount/4 with an empty session" do
    test "assigns the documented defaults (theme nil, sidebar open, no sections)" do
      socket = mount(%{})

      assert socket.assigns.current_theme == nil
      assert socket.assigns.sidebar_open == true
      assert socket.assigns.sidebar_section_states == %{}
    end

    test "treats a session that only has the preferences key present as empty" do
      socket = mount(%{"backpex_preferences" => %{}})

      assert socket.assigns.current_theme == nil
      assert socket.assigns.sidebar_open == true
      assert socket.assigns.sidebar_section_states == %{}
    end

    test "returns `{:cont, socket}` so subsequent hooks still run" do
      # The public contract of a LiveView `on_mount` hook is the `{:cont | :halt,
      # socket}` tuple. Pin the shape here so refactors cannot silently change
      # semantics (e.g. to `{:halt, ...}`).
      assert {:cont, %Socket{}} = InitAssigns.on_mount(:default, %{}, %{}, build_socket())
    end
  end

  describe "on_mount/4 with preference values present in the session" do
    test "mirrors the stored theme, sidebar_open, and sidebar_section_states" do
      session = %{
        "backpex_preferences" => %{
          "global" => %{
            "theme" => "dark",
            "sidebar_open" => false,
            "sidebar_section" => %{"users" => true, "blog" => false}
          }
        }
      }

      socket = mount(session)

      assert socket.assigns.current_theme == "dark"
      assert socket.assigns.sidebar_open == false
      assert socket.assigns.sidebar_section_states == %{"users" => true, "blog" => false}
    end

    test "accepts non-boolean sidebar_open as-is (adapter has no schema enforcement)" do
      # The Session adapter is a dumb key/value store — it returns whatever is
      # stored. Document the current behavior: `sidebar_open` can hold any term
      # if the host app writes one. Layout components are responsible for
      # coercing.
      session = %{"backpex_preferences" => %{"global" => %{"sidebar_open" => "nope"}}}
      socket = mount(session)
      assert socket.assigns.sidebar_open == "nope"
    end
  end

  describe "on_mount/4 with a malformed session" do
    test "falls back to defaults when `backpex_preferences` is a binary" do
      # Pathological but possible: a host app stomps on the session key with a
      # non-map. The Session adapter's `root/1` guards against this and the
      # on_mount hook must not crash.
      socket = mount(%{"backpex_preferences" => "oops"})

      assert socket.assigns.current_theme == nil
      assert socket.assigns.sidebar_open == true
      assert socket.assigns.sidebar_section_states == %{}
    end

    test "falls back to defaults when `backpex_preferences` is explicitly nil" do
      socket = mount(%{"backpex_preferences" => nil})

      assert socket.assigns.current_theme == nil
      assert socket.assigns.sidebar_open == true
      assert socket.assigns.sidebar_section_states == %{}
    end

    test "returns the stored value unchanged when the theme slot holds a non-string" do
      # The Session adapter doesn't type-check; surfacing the raw value lets
      # layout code decide whether to coerce. Pin current behavior so a silent
      # change to coerce-at-read surfaces here.
      session = %{"backpex_preferences" => %{"global" => %{"theme" => 42}}}
      socket = mount(session)
      assert socket.assigns.current_theme == 42
    end

    test "sidebar_section_states falls back to %{} when the stored subtree is not a map" do
      # `Preferences.get_map/3` must degrade to `%{}` rather than returning a
      # scalar for the sidebar_section sub-tree — otherwise callers that
      # pattern-match on a map in the layout crash.
      session = %{
        "backpex_preferences" => %{"global" => %{"sidebar_section" => "not-a-map"}}
      }

      socket = mount(session)
      assert socket.assigns.sidebar_section_states == %{}
    end
  end

  describe "on_mount/4 with a custom Preferences adapter" do
    test "the adapter's value for global.theme wins over anything in the session" do
      # Route every key through StubAdapter and seed a value for `global.theme`.
      # Despite the session also holding a theme, the adapter result must win —
      # this is what lets a DB-backed adapter override session state.
      Application.put_env(:backpex, Backpex.Preferences, adapters: [{:default, StubAdapter, []}])

      StubAdapter.set(%{"global.theme" => "cupcake"})

      session = %{"backpex_preferences" => %{"global" => %{"theme" => "dark"}}}
      socket = mount(session)

      assert socket.assigns.current_theme == "cupcake"
    end

    test "falls back to the :default option when the adapter reports `:not_found` for sidebar_open" do
      # StubAdapter returns `:not_found` for unknown keys. Verify the caller's
      # `default: true` option reaches the value.
      Application.put_env(:backpex, Backpex.Preferences, adapters: [{:default, StubAdapter, []}])

      StubAdapter.set(%{})

      socket = mount(%{})
      assert socket.assigns.sidebar_open == true
    end
  end

  describe "on_mount/4 hooks the current URL into :handle_params" do
    test "attaches a handle_params hook that stores the URL on :current_url" do
      # The hook itself runs on each `handle_params`. We can't drive the real
      # lifecycle without a mounted LiveView, but we can verify the attachment
      # happened — future changes that drop the hook break this test.
      socket = mount(%{})

      hooks = socket.private.lifecycle.handle_params
      assert Enum.any?(hooks, fn hook -> hook.id == :current_url end)
    end
  end

  # A recording adapter: every read reports the full context back to the test
  # process so we can assert on both `ctx.session` and `ctx.assigns`. This is
  # how we verify that InitAssigns builds the Context from `socket.assigns`
  # (not just the raw session) and passes it through to the dispatcher.
  defmodule RecordingAdapter do
    @moduledoc false
    @behaviour Adapter

    @impl Adapter
    def get(ctx, key, _opts) do
      send(self(), {:recorded_get, key, ctx})
      {:ok, :not_found}
    end

    @impl Adapter
    def get_map(ctx, prefix, _opts) do
      send(self(), {:recorded_get_map, prefix, ctx})
      {:ok, %{}}
    end

    @impl Adapter
    def put(_ctx, _key, _value, _opts), do: {:ok, [:noop]}
  end

  describe "on_mount/4 threads socket.assigns through the Context" do
    test "every preference read receives a Context carrying the session and socket.assigns" do
      # The core DX guarantee: an Ecto-backed identity resolver should be able
      # to read `ctx.assigns.current_scope` (or whatever the host app's auth
      # hook put on the socket) rather than re-implement session-token lookup.
      Application.put_env(:backpex, Backpex.Preferences, adapters: [{:default, RecordingAdapter, []}])

      current_user = %{id: 42, email: "user@example.com"}

      socket = %{build_socket() | assigns: %{__changed__: %{}, current_user: current_user}}
      session = %{"some" => "session-data"}

      _mounted_socket = mount(session, socket)

      # Drain every recorded call and assert the Context shape.
      contexts =
        Stream.repeatedly(fn ->
          receive do
            {:recorded_get, _key, ctx} -> ctx
            {:recorded_get_map, _prefix, ctx} -> ctx
          after
            0 -> nil
          end
        end)
        |> Stream.take_while(&(&1 != nil))
        |> Enum.to_list()

      # InitAssigns reads at least three preferences: theme, sidebar_open,
      # and the sidebar_section prefix map. Every one of them must see the
      # same socket.assigns snapshot.
      assert length(contexts) >= 3

      Enum.each(contexts, fn ctx ->
        assert %Backpex.Preferences.Context{} = ctx
        assert ctx.session == session
        assert ctx.assigns[:current_user] == current_user
      end)
    end
  end
end
