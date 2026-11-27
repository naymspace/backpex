defmodule DemoWeb.BrowserCase do
  @moduledoc """
  The case for browser tests. It runs the tests in Chromium with Fluffy's native API.
  """
  use ExUnit.CaseTemplate

  using opts do
    quote do
      use Playwright.Test, unquote(opts)
      use Fluffy.Assert

      import Fluffy
      import Fluffy.Locator

      setup do
        %{session: start_session(:playwright)}
      end
    end
  end

  setup tags do
    Demo.DataCase.setup_sandbox(tags)
    :ok
  end
end
