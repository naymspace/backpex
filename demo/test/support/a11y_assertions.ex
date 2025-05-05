defmodule DemoWeb.A11yAssertions do
  @moduledoc """
  Provides a11y assertions.
  """
  defmacro __using__(_opts) do
    quote do
      alias PhoenixTest.Playwright.Frame

      def assert_a11y(session) do
        Frame.evaluate(session.frame_id, A11yAudit.JS.axe_core())

        results =
          session.frame_id
          |> Frame.evaluate(A11yAudit.JS.await_audit_results())
          |> A11yAudit.Results.from_json()

        A11yAudit.Assertions.assert_no_violations(results)

        session
      end
    end
  end
end
