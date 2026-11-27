{:ok, _apps} = Application.ensure_all_started(:ex_machina)

ExUnit.configure(exclude: [playwright: true])
ExUnit.start()
