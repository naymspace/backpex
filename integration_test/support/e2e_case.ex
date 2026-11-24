defmodule Backpex.E2ECase do
  @moduledoc """
  The case for browser tests of the test app. It runs the tests in Chromium with Fluffy's native API and tags them
  `:e2e`, so they only run with `mix test --only e2e`.

  The browser loads the assets of `bun run e2e:assets` from `tmp/e2e/assets`.
  """
  use ExUnit.CaseTemplate

  using opts do
    quote do
      use Playwright.Test, unquote(opts)
      use Fluffy.Assert
      use Phoenix.VerifiedRoutes, endpoint: Backpex.Test.Endpoint, router: Backpex.Test.Router

      import Backpex.E2ECase
      import Backpex.Test.EctoFactory
      import Fluffy
      import Fluffy.Locator

      @moduletag :e2e

      setup do
        %{session: start_session(:playwright)}
      end
    end
  end

  setup tags do
    Backpex.DataCase.setup_sandbox(tags)
    :ok
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
