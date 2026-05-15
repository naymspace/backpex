defmodule Backpex.PreferencesTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Plug.Test

  alias Backpex.Preferences
  alias Backpex.Preferences.Adapter
  alias Backpex.Preferences.Adapters.Session
  alias Backpex.Preferences.Context
  alias Backpex.Preferences.Keys
  alias Backpex.Preferences.LiveView, as: PreferenceLiveView
  alias Phoenix.LiveView.Socket
  alias Phoenix.LiveView.Utils, as: LiveViewUtils

  doctest Backpex.Preferences

  describe "session_key/0" do
    test "returns the session key used by the session adapter" do
      assert Preferences.session_key() == Session.session_key()
      assert Preferences.session_key() == "backpex_preferences"
    end
  end

  describe "get/3 (session map form)" do
    test "reads a value from the backing session" do
      session = %{"backpex_preferences" => %{"global" => %{"theme" => "dark"}}}
      assert Preferences.get(session, Keys.theme()) == "dark"
    end

    test "returns the :default option when the key is missing" do
      assert Preferences.get(%{}, Keys.theme(), default: "light") == "light"
    end

    test "returns nil when the key is missing and no default is set" do
      assert Preferences.get(%{}, Keys.theme()) == nil
    end

    test "reads colon-form keys without dot-collision on embedded module names" do
      session = %{
        "backpex_preferences" => %{
          "resource" => %{
            "MyApp.UserLive" => %{"columns" => %{"name" => true}}
          }
        }
      }

      assert Preferences.get(session, Keys.columns(MyApp.UserLive)) == %{"name" => true}
    end
  end

  describe "get/3 (Context form)" do
    test "accepts a Context built from a session map" do
      session = %{"backpex_preferences" => %{"global" => %{"theme" => "dark"}}}
      ctx = Context.from_mount(session)
      assert Preferences.get(ctx, Keys.theme()) == "dark"
    end
  end

  describe "get_map/3" do
    test "returns the nested map at the given prefix" do
      session = %{
        "backpex_preferences" => %{
          "global" => %{"sidebar_section" => %{"blog" => true, "settings" => false}}
        }
      }

      assert Preferences.get_map(session, Keys.sidebar_section_prefix()) == %{
               "blog" => true,
               "settings" => false
             }
    end

    test "returns an empty map when the prefix is absent" do
      assert Preferences.get_map(%{}, Keys.sidebar_section_prefix()) == %{}
    end

    test "returns an empty map when the value at the prefix is not a map" do
      session = %{"backpex_preferences" => %{"global" => %{"theme" => "dark"}}}
      assert Preferences.get_map(session, Keys.theme()) == %{}
    end
  end

  describe "put_batch/2" do
    test "returns side effects that compose across writes to the same session key" do
      ctx = Context.from_mount(%{"backpex_preferences" => %{"global" => %{"theme" => "light"}}})

      entries = [
        {Keys.theme(), "dark"},
        {Keys.sidebar_open(), true}
      ]

      # Pretend we're in a controller so the Session adapter will emit put_session effects.
      ctx = %{ctx | source: :controller}

      assert {:ok, effects} = Preferences.put_batch(ctx, entries)

      # The last put_session effect carries the fully-merged map.
      last_effect = List.last(effects)
      assert {:put_session, "backpex_preferences", merged} = last_effect
      assert merged == %{"global" => %{"theme" => "dark", "sidebar_open" => true}}
    end

    test "returns {:error, {key, reason}} on the first adapter refusal (best-effort, first-error-wins)" do
      # :mount source → Session adapter returns :requires_http.
      ctx = Context.from_mount(%{})
      theme_key = Keys.theme()
      assert {:error, {^theme_key, :requires_http}} = Preferences.put_batch(ctx, [{theme_key, "dark"}])
    end
  end

  describe "parse_key/1 (legacy alias)" do
    test "delegates to Backpex.Preferences.Key" do
      columns_segments = MyApp.UserLive |> Keys.columns() |> Preferences.parse_key()

      assert Preferences.parse_key(Keys.theme()) == ["global", "theme"]
      assert columns_segments == ["resource", "MyApp.UserLive", "columns"]
    end
  end

  describe "put/4" do
    test "Plug.Conn origin with the Session adapter persists through put_session" do
      conn = conn(:post, "/") |> Plug.Test.init_test_session(%{})

      assert {:ok, %Plug.Conn{} = conn} = Preferences.put(conn, Keys.theme(), "dark")

      assert Plug.Conn.get_session(conn, Preferences.session_key()) ==
               %{"global" => %{"theme" => "dark"}}
    end

    test "socket origin with the Session adapter queues a push_event fallback (:requires_http)" do
      socket = %Socket{
        assigns: %{__changed__: %{}},
        private: %{live_temp: %{}}
      }

      assert {:ok, %Socket{} = socket} =
               Preferences.put(socket, Keys.theme(), "dark")

      # Use the event name constant so the assertion tracks any change to
      # LiveView.event_name/0 — this test is a pin for the wire contract.
      assert LiveViewUtils.get_push_events(socket) ==
               [[PreferenceLiveView.event_name(), %{key: Keys.theme(), value: "dark"}]]
    end

    test "adapter crash surfaces as {:error, _} without raising" do
      with_adapters([{:default, Backpex.PreferencesTest.CrashingAdapter, []}], fn ->
        conn = conn(:post, "/") |> Plug.Test.init_test_session(%{})

        log =
          capture_log(fn ->
            assert {:error, {:exception, %RuntimeError{message: "boom"}}} =
                     Preferences.put(conn, Keys.theme(), "dark")
          end)

        assert log =~ "Backpex.Preferences"
        assert log =~ "raised in put/4"
      end)
    end

    test "adapter returning {:error, reason} is surfaced to the caller" do
      with_adapters([{:default, Backpex.Test.RejectingPreferencesAdapter, []}], fn ->
        conn = conn(:post, "/") |> Plug.Test.init_test_session(%{})

        log =
          capture_log(fn ->
            assert {:error, :rejected} = Preferences.put(conn, Keys.theme(), "dark")
          end)

        assert log =~ "Backpex.Preferences"
        assert log =~ "refused put/4"
      end)
    end

    test "adapter returning {:error, :unidentified} is surfaced unchanged" do
      with_adapters([{:default, Backpex.PreferencesTest.UnidentifiedAdapter, []}], fn ->
        conn = conn(:post, "/") |> Plug.Test.init_test_session(%{})

        log =
          capture_log(fn ->
            assert {:error, :unidentified} = Preferences.put(conn, Keys.theme(), "dark")
          end)

        assert log =~ ":unidentified"
      end)
    end

    test "socket-origin {:put_session, _, _} is rerouted through push_event with a warning" do
      with_adapters([{:default, Backpex.PreferencesTest.SessionFromSocketAdapter, []}], fn ->
        socket = %Socket{
          assigns: %{__changed__: %{}},
          private: %{live_temp: %{}}
        }

        {result, log} =
          with_log(fn ->
            Preferences.put(socket, "k", %{a: 1})
          end)

        assert {:ok, %Socket{} = socket} = result

        # The {:put_session, _, _} effect from a socket-origin call must
        # round-trip through the browser, not vanish.
        assert LiveViewUtils.get_push_events(socket) ==
                 [[PreferenceLiveView.event_name(), %{key: "k", value: %{a: 1}}]]

        assert log =~ "routing through push_event fallback"
      end)
    end
  end

  describe "fetch/3" do
    test "returns {:ok, value} for a stored value" do
      session = %{"backpex_preferences" => %{"global" => %{"theme" => "dark"}}}
      assert Preferences.fetch(session, Keys.theme()) == {:ok, "dark"}
    end

    test "returns :error when nothing is stored" do
      assert Preferences.fetch(%{}, Keys.theme()) == :error
    end

    test "returns {:error, reason} and logs a warning on adapter error" do
      with_adapters([{:default, Backpex.PreferencesTest.RaisingGetAdapter, []}], fn ->
        log =
          capture_log(fn ->
            assert {:error, :boom} = Preferences.fetch(%{}, Keys.theme())
          end)

        assert log =~ "Backpex.Preferences"
        assert log =~ "fetch/3"
      end)
    end

    test "collapses {:error, :unidentified} to :error without logging" do
      # `Backpex.Preferences.Adapter` defines `:unidentified` on reads as
      # "treat as not found" — fetch/3 must return :error (matching the
      # stored-but-missing case) and must NOT log a warning, because the
      # condition is expected (anonymous visitors, background jobs, etc.).
      with_adapters([{:default, Backpex.PreferencesTest.UnidentifiedAdapter, []}], fn ->
        log =
          capture_log(fn ->
            assert Preferences.fetch(%{}, Keys.theme()) == :error
          end)

        refute log =~ "Backpex.Preferences"
        refute log =~ ":unidentified"
      end)
    end
  end

  describe "get/3 logs warnings on adapter error" do
    test "falls back to default AND logs when the adapter returns {:error, _}" do
      with_adapters([{:default, Backpex.PreferencesTest.RaisingGetAdapter, []}], fn ->
        log =
          capture_log(fn ->
            assert Preferences.get(%{}, Keys.theme(), default: "light") == "light"
          end)

        assert log =~ "Backpex.Preferences"
        assert log =~ "falling back to default"
      end)
    end
  end

  describe "identity resolver error path" do
    test "a raising resolver triggers a Logger.warning and resolves to :unidentified" do
      prior = Application.get_env(:backpex, Backpex.Preferences)

      Application.put_env(:backpex, Backpex.Preferences,
        adapters: [{:default, Session, []}],
        identity: {Backpex.PreferencesTest.RaisingIdentity, :resolve, []}
      )

      on_exit(fn ->
        case prior do
          nil -> Application.delete_env(:backpex, Backpex.Preferences)
          value -> Application.put_env(:backpex, Backpex.Preferences, value)
        end
      end)

      log =
        capture_log(fn ->
          # Reading goes through the resolver — a raise inside it is caught
          # and falls back to :unidentified. The warning is the operator signal.
          assert Preferences.get(%{}, Keys.theme(), default: "light") == "light"
        end)

      assert log =~ "preferences"
      assert log =~ "identity resolver"
      assert log =~ ":unidentified"
    end
  end

  # --- helpers -----------------------------------------------------------

  defp with_adapters(adapters, fun) do
    prior = Application.get_env(:backpex, Backpex.Preferences)

    Application.put_env(:backpex, Backpex.Preferences, adapters: adapters)

    try do
      fun.()
    after
      case prior do
        nil -> Application.delete_env(:backpex, Backpex.Preferences)
        value -> Application.put_env(:backpex, Backpex.Preferences, value)
      end
    end
  end

  # --- fake adapters -----------------------------------------------------

  defmodule CrashingAdapter do
    @moduledoc false
    @behaviour Adapter

    @impl Adapter
    def get(_ctx, _key, _opts), do: {:ok, :not_found}
    @impl Adapter
    def get_map(_ctx, _prefix, _opts), do: {:ok, %{}}
    @impl Adapter
    def put(_ctx, _key, _value, _opts), do: raise("boom")
  end

  defmodule UnidentifiedAdapter do
    @moduledoc false
    @behaviour Adapter

    @impl Adapter
    def get(_ctx, _key, _opts), do: {:error, :unidentified}
    @impl Adapter
    def get_map(_ctx, _prefix, _opts), do: {:error, :unidentified}
    @impl Adapter
    def put(_ctx, _key, _value, _opts), do: {:error, :unidentified}
  end

  defmodule SessionFromSocketAdapter do
    @moduledoc false
    # Pathological adapter that emits {:put_session, _, _} from a socket
    # origin — exercises the dispatcher's push_event fallback path.
    @behaviour Adapter

    @impl Adapter
    def get(_ctx, _key, _opts), do: {:ok, :not_found}
    @impl Adapter
    def get_map(_ctx, _prefix, _opts), do: {:ok, %{}}
    @impl Adapter
    def put(_ctx, key, value, _opts), do: {:ok, [{:put_session, key, value}]}
  end

  defmodule RaisingGetAdapter do
    @moduledoc false
    @behaviour Adapter

    @impl Adapter
    def get(_ctx, _key, _opts), do: {:error, :boom}
    @impl Adapter
    def get_map(_ctx, _prefix, _opts), do: {:error, :boom}
    @impl Adapter
    def put(_ctx, _key, _value, _opts), do: {:ok, [:noop]}
  end

  defmodule RaisingIdentity do
    @moduledoc false
    def resolve(_ctx), do: raise("identity resolver boom")
  end
end
