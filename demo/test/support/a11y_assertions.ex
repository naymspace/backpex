defmodule DemoWeb.A11yAssertions do
  @moduledoc """
  Provides a11y assertions.
  """
  defmacro __using__(_opts) do
    quote do
      alias PhoenixTest.Playwright.Frame

      def assert_a11y(session) do
        Frame.evaluate(session.frame_id, A11yAudit.JS.axe_core())

        {:ok, json} = Frame.evaluate(session.frame_id, "axe.run()")

        json
        |> A11yAudit.Results.from_json()
        |> A11yAudit.Assertions.assert_no_violations()

        session
      end
    end
  end
end
