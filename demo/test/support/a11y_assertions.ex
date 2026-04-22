defmodule DemoWeb.A11yAssertions do
  @moduledoc """
  Provides a11y assertions.
  """
  defmacro __using__(_opts) do
    quote do
      alias PlaywrightEx.Frame

      def assert_a11y(session) do
        Frame.evaluate(session.frame_id, expression: A11yAudit.JS.axe_core(), timeout: timeout())

        {:ok, json} = Frame.evaluate(session.frame_id, expression: "axe.run()", timeout: timeout())

        json
        |> A11yAudit.Results.from_json()
        |> A11yAudit.Assertions.assert_no_violations()

        session
      end
    end
  end
end
