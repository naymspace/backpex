defmodule DemoWeb.A11yAssertions do
  @moduledoc """
  Provides a11y assertions.
  """
  defmacro __using__(_opts) do
    quote do
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

      def assert_a11y(%Fluffy.Session{} = session) do
        session
        |> Fluffy.Playwright.add_script_tag(content: A11yAudit.JS.axe_core())
        |> Fluffy.Playwright.evaluate(@axe_run_without_animations)
        |> A11yAudit.Results.from_json()
        |> A11yAudit.Assertions.assert_no_violations()

        session
      end
    end
  end
end
