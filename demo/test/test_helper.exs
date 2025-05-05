{:ok, _apps} = Application.ensure_all_started(:ex_machina)

Application.put_env(:phoenix_test, :base_url, DemoWeb.Endpoint.url())

ExUnit.configure(exclude: [external: true])
ExUnit.start()
