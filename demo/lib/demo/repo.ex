defmodule Demo.Repo do
  use Ecto.Repo,
    otp_app: :demo,
    adapter: Ecto.Adapters.Postgres
end

defmodule Demo.RepoAsh do
  use AshPostgres.Repo, otp_app: :demo

  def installed_extensions do
    ["ash-functions"]
  end
end
