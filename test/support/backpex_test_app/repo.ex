defmodule BackpexTestApp.Repo do
  use Ecto.Repo,
    otp_app: :backpex,
    adapter: Ecto.Adapters.Postgres
end
