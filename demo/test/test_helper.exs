{:ok, _apps} = Application.ensure_all_started(:ex_machina)

ExUnit.start()
