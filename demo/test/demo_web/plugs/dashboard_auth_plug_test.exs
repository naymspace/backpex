defmodule DemoWeb.DashboardAuthPlugTest do
  # Not async: the tests change the application and the system environment.
  use DemoWeb.ConnCase, async: false

  alias DemoWeb.DashboardAuthPlug

  @dashboard_path "/phoenix_live_dashboard/home"
  @username "dashboard-test-user"
  @password "dashboard-test-password"

  setup do
    config = Application.fetch_env!(:demo, DashboardAuthPlug)
    on_exit(fn -> Application.put_env(:demo, DashboardAuthPlug, config) end)
  end

  describe "auth required with credentials" do
    setup do
      put_config(required: true, username: @username, password: @password)
    end

    test "accepts the configured credentials", %{conn: conn} do
      conn = conn |> with_credentials(@username, @password) |> get(@dashboard_path)

      assert html_response(conn, 200)
    end

    test "rejects a request without credentials", %{conn: conn} do
      conn = get(conn, @dashboard_path)

      assert response(conn, 401)
      assert conn.halted
      assert ["Basic realm=" <> _rest] = get_resp_header(conn, "www-authenticate")
    end

    test "rejects wrong credentials", %{conn: conn} do
      for {username, password} <- [{@username, "wrong"}, {"wrong", @password}, {"", ""}] do
        conn = conn |> with_credentials(username, password) |> get(@dashboard_path)

        assert response(conn, 401)
        assert conn.halted
      end
    end
  end

  describe "auth required without credentials (prod without the environment variables)" do
    test "answers 404, also for requests that send credentials", %{conn: conn} do
      configs = [
        [required: true, username: nil, password: nil],
        [required: true, username: @username, password: nil],
        [required: true, username: nil, password: @password],
        [required: true, username: "", password: ""],
        [required: true],
        # anything but an explicit `required: false` counts as required
        [username: nil, password: nil],
        []
      ]

      requests = [& &1, &with_credentials(&1, "", ""), &with_credentials(&1, @username, @password)]

      for config <- configs, request <- requests do
        put_config(config)
        conn = conn |> request.() |> get(@dashboard_path)

        assert response(conn, 404)
        assert conn.halted
        assert get_resp_header(conn, "www-authenticate") == []
      end
    end
  end

  describe "auth not required (dev and test)" do
    test "passes the request through", %{conn: conn} do
      put_config(required: false, username: nil, password: nil)

      assert conn |> get(@dashboard_path) |> html_response(200)
    end
  end

  describe "config/runtime.exs" do
    test "requires auth in prod and has no fallback credentials" do
      config = read_runtime_config(:prod, %{})

      assert config[:required] == true
      assert config[:username] == nil
      assert config[:password] == nil
    end

    test "has no opt-out in prod" do
      assert read_runtime_config(:prod, %{"DASHBOARD_AUTH_ENABLED" => "false"})[:required] == true
    end

    test "reads the credentials from the environment" do
      env = %{"DASHBOARD_AUTH_USERNAME" => @username, "DASHBOARD_AUTH_PASSWORD" => @password}
      config = read_runtime_config(:prod, env)

      assert config[:username] == @username
      assert config[:password] == @password
    end

    test "does not require auth in dev and test unless enabled" do
      for config_env <- [:dev, :test] do
        assert read_runtime_config(config_env, %{})[:required] == false
        assert read_runtime_config(config_env, %{"DASHBOARD_AUTH_ENABLED" => "true"})[:required] == true
      end
    end
  end

  defp put_config(config), do: Application.put_env(:demo, DashboardAuthPlug, config)

  defp with_credentials(conn, username, password) do
    put_req_header(conn, "authorization", Plug.BasicAuth.encode_basic_auth(username, password))
  end

  # Evaluates config/runtime.exs for the given environment with only the given dashboard variables set and
  # returns the plug's config. The secrets that dev and prod require are placeholders during the call.
  defp read_runtime_config(config_env, dashboard_env) do
    dashboard_vars = ~w(DASHBOARD_AUTH_ENABLED DASHBOARD_AUTH_USERNAME DASHBOARD_AUTH_PASSWORD)
    placeholders = %{"SECRET_KEY_BASE" => "placeholder", "LIVE_VIEW_SIGNING_SALT" => "placeholder"}
    env = dashboard_vars |> Map.new(&{&1, nil}) |> Map.merge(placeholders) |> Map.merge(dashboard_env)
    previous = Map.new(env, fn {name, _value} -> {name, System.get_env(name)} end)

    try do
      put_system_env(env)

      "config/runtime.exs"
      |> Config.Reader.read!(env: config_env)
      |> get_in([:demo, DashboardAuthPlug])
    after
      put_system_env(previous)
    end
  end

  defp put_system_env(env) do
    Enum.each(env, fn
      {name, nil} -> System.delete_env(name)
      {name, value} -> System.put_env(name, value)
    end)
  end
end
