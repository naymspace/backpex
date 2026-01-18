{:ok, _apps} = Application.ensure_all_started(:ex_machina)
{:ok, _pid} = PhoenixTest.Playwright.Supervisor.start_link()

Application.put_env(:phoenix_test, :base_url, DemoWeb.Endpoint.url())

ExUnit.configure(exclude: [playwright: true])
ExUnit.start()
