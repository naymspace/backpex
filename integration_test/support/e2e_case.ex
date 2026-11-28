defmodule Backpex.E2ECase do
  @moduledoc """
  The case for browser tests of the test app. It runs the tests with `PhoenixTest.Playwright` in Chromium, or in the
  browser `PW_BROWSER` names (`firefox`, `webkit`), and tags them `:e2e`, so they only run with `mix test --only e2e`.

  The browser loads the assets of `bun run e2e:assets` from `tmp/e2e/assets`.
  """
  use ExUnit.CaseTemplate

  alias PhoenixTest.Playwright.Config
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

  @doc """
  Runs axe-core on the current page and fails on any accessibility violation.

  Chromium and WebKit audit the markup; Firefox skips the audit. In Firefox, about one in four audits of a form whose
  inputs have an `aria-labelledby` with two ids (`InlineCRUD`, `HasMany`) crashed the page, while a page with only such
  an input did not. Firefox also does not support the customizable select yet, so axe flagged its unused `<button>`.
  """
  def assert_a11y(session) do
    if Config.global(:browser) == :firefox, do: session, else: audit(session)
  end

  defp audit(session) do
    timeout = Config.global(:timeout)

    Frame.evaluate(session.frame_id, expression: A11yAudit.JS.axe_core(), timeout: timeout)
    {:ok, json} = Frame.evaluate(session.frame_id, expression: @axe_run_without_animations, timeout: timeout)

    json
    |> A11yAudit.Results.from_json()
    |> A11yAudit.Assertions.assert_no_violations()

    session
  end
end
