defmodule DemoWeb.A11yAssertions do
  @moduledoc """
  Provides a11y assertions.
  """
  defmacro __using__(_opts) do
    quote do
      alias PlaywrightEx.Frame

      # Waits for finite, time-based animations (e.g. a dropdown fading in) before the audit, so
      # axe measures the final colors instead of colors blended with the background. Infinite and
      # scroll-driven animations (whose end time is not a number) never finish.
      @axe_run_after_animations """
      Promise.all(
        document.getAnimations()
          .filter((animation) => Number.isFinite(animation.effect?.getComputedTiming().endTime))
          .map((animation) => animation.finished.catch(() => null))
      ).then(() => axe.run())
      """

      def assert_a11y(session) do
        Frame.evaluate(session.frame_id, expression: A11yAudit.JS.axe_core(), timeout: timeout())

        {:ok, json} = Frame.evaluate(session.frame_id, expression: @axe_run_after_animations, timeout: timeout())

        json
        |> A11yAudit.Results.from_json()
        |> A11yAudit.Assertions.assert_no_violations()

        session
      end
    end
  end
end
