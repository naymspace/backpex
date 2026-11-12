defmodule Backpex.Test.Repo do
  @moduledoc """
  The PostgreSQL repo of the test app. Its migrations live in `integration_test/support/app/priv/migrations` and run in
  `test_helper.exs`.
  """
  use Ecto.Repo, otp_app: :backpex, adapter: Ecto.Adapters.Postgres
end

defmodule Backpex.Test.ErrorHTML do
  @moduledoc false
  def render(template, _assigns), do: Phoenix.Controller.status_message_from_template(template)
end

defmodule Backpex.Test.Sandbox do
  @moduledoc """
  Allows the LiveViews of a browser test to use the database connection of the test.

  `PhoenixTest.Playwright.Case` puts the sandbox metadata of the test into the user agent of the browser. Tests that use
  `Phoenix.LiveViewTest` need no allowance, the LiveView process has the test process in its `$callers`.
  """
  import Phoenix.LiveView

  def on_mount(:default, _params, _session, socket) do
    if connected?(socket) do
      socket
      |> get_connect_info(:user_agent)
      |> Phoenix.Ecto.SQL.Sandbox.allow(Ecto.Adapters.SQL.Sandbox)
    end

    {:cont, socket}
  end
end

defmodule Backpex.Test.Endpoint do
  @moduledoc """
  The endpoint of the test app. It serves the LiveResources in `Backpex.Test.Router` to `Phoenix.LiveViewTest` and,
  with the assets built by `bun run e2e:assets`, to the browser tests.
  """
  use Phoenix.Endpoint, otp_app: :backpex

  @session_options [store: :cookie, key: "_backpex_test_key", signing_salt: "backpex_test", same_site: "Lax"]

  socket "/live", Phoenix.LiveView.Socket, websocket: [connect_info: [:user_agent, session: @session_options]]

  plug Phoenix.Ecto.SQL.Sandbox

  plug Plug.Static, at: "/assets", from: Path.expand("../../../tmp/e2e/assets", __DIR__)
  # An MFA tuple, so the directory of the current `MIX_TEST_PARTITION` is resolved per request.
  plug Plug.Static, at: "/", from: {Backpex.Test.Uploads, :dir, []}, only: ~w(uploads)

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug Backpex.Test.Router
end
