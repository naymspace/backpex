defmodule DemoWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use DemoWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  alias PhoenixTest.Playwright.Frame

  using do
    quote do
      # The default endpoint for testing
      @endpoint DemoWeb.Endpoint

      use DemoWeb, :verified_routes

      import PhoenixTest

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import DemoWeb.ConnCase

      define_a11y_assertions()
    end
  end

  setup tags do
    Demo.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  defmacro define_a11y_assertions do
    quote do
      alias PhoenixTest.Playwright.Frame

      def assert_a11y(session) do
        Frame.evaluate(session.frame_id, A11yAudit.JS.axe_core())

        results =
          session.frame_id
          |> Frame.evaluate("axe.run()")
          |> A11yAudit.Results.from_json()

        A11yAudit.Assertions.assert_no_violations(results)

        session
      end
    end
  end
end
