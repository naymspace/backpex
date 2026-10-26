defmodule DemoWeb.A11yAssertions do
  @moduledoc """
  Provides a11y assertions.
  """
  defmacro __using__(_opts) do
    quote do
      alias PlaywrightEx.Frame

      # Turns off animations and transitions during the audit (e.g. a dropdown fading in), so axe
      # measures the final colors instead of colors blended with the background.
      @axe_run_without_animations """
      (async () => {
        const style = document.createElement('style')
        style.textContent = '*, *::before, *::after { animation: none !important; transition: none !important; }'
        document.head.appendChild(style)
        try {
          return await axe.run()
        } finally {
          style.remove()
        }
      })()
      """

      def assert_a11y(session) do
        Frame.evaluate(session.frame_id, expression: A11yAudit.JS.axe_core(), timeout: timeout())

        {:ok, json} = Frame.evaluate(session.frame_id, expression: @axe_run_without_animations, timeout: timeout())

        json
        |> A11yAudit.Results.from_json()
        |> A11yAudit.Assertions.assert_no_violations()

        session
      end
    end
  end
end
