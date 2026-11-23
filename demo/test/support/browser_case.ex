defmodule DemoWeb.BrowserCase do
  @moduledoc """
  The case for browser tests. It runs the tests in Chromium with `Fluffy.PhoenixTest`.
  """
  use ExUnit.CaseTemplate

  using opts do
    quote do
      use Playwright.Test, unquote(opts)

      import Fluffy.PhoenixTest

      setup do
        %{conn: start_session(:playwright)}
      end
    end
  end

  setup tags do
    Demo.DataCase.setup_sandbox(tags)
    :ok
  end
end
