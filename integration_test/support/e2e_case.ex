defmodule Backpex.E2ECase do
  @moduledoc """
  The case for browser tests of the test app. It runs the tests with `PhoenixTest.Playwright` in Chromium, or in the
  browser `PW_BROWSER` names (`firefox`, `webkit`), and tags them `:e2e`, so they only run with `mix test --only e2e`.

  The browser loads the assets of `bun run e2e:assets` from `tmp/e2e/assets`.
  """
  use ExUnit.CaseTemplate

  alias PlaywrightEx.Frame

  using opts do
    quote do
      use PhoenixTest.Playwright.Case, unquote(opts)
      use Phoenix.VerifiedRoutes, endpoint: Backpex.Test.Endpoint, router: Backpex.Test.Router

      import Backpex.E2ECase
      import Backpex.Test.EctoFactory

      @moduletag :e2e
    end
  end

  # Turns off animations and transitions during the audit (e.g. a dropdown fading in), so axe measures the final colors
  # instead of colors blended with the background.
  #
  # The selects render a `<button>` with `<selectedcontent>` for the customizable select (`appearance: base-select`). A
  # browser without it (Firefox) shows the native dropdown instead and leaves `<selectedcontent>` empty, so axe would
  # flag a button without a name that the select does not use. Such browsers skip that button.
  @axe_run_without_animations """
  (async () => {
    const style = document.createElement('style')
    style.textContent = '*, *::before, *::after { animation: none !important; transition: none !important; }'
    document.head.appendChild(style)
    try {
      const context = CSS.supports('appearance', 'base-select') ? document : { exclude: ['select > button'] }
      return await axe.run(context)
    } finally {
      style.remove()
    }
  })()
  """

  @doc """
  Runs axe-core on the current page and fails on any accessibility violation.
  """
  def assert_a11y(session) do
    timeout = PhoenixTest.Playwright.Config.global(:timeout)

    Frame.evaluate(session.frame_id, expression: A11yAudit.JS.axe_core(), timeout: timeout)
    {:ok, json} = Frame.evaluate(session.frame_id, expression: @axe_run_without_animations, timeout: timeout)

    json
    |> A11yAudit.Results.from_json()
    |> A11yAudit.Assertions.assert_no_violations()

    session
  end
end
