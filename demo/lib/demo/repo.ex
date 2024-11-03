defmodule Demo.Repo do
  use Ecto.Repo,
    otp_app: :demo,
    adapter: Ecto.Adapters.Postgres

  def installed_extensions do
    ["ash-functions"]
  end

  def min_pg_version do
    %Version{major: 16, minor: 0, patch: 0}
  end
end
