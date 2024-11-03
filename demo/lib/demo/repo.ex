defmodule Demo.Repo do
  use Ecto.Repo,
    otp_app: :demo,
    adapter: Ecto.Adapters.Postgres

  def installed_extensions do
    ["ash-functions"]
  end
end
