defmodule Demo.Repo do
  use AshPostgres.Repo,
    otp_app: :demo

  def installed_extensions do
    ["ash-functions"]
  end
end
