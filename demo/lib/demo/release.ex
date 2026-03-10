defmodule Demo.Release do
  @moduledoc false

  @app :demo

  defp init(start_apps) do
    Application.load(@app)
    Enum.each(start_apps, &Application.ensure_all_started/1)
  end

  defp repos, do: Application.fetch_env!(@app, :ecto_repos)

  @doc """
  Migrate the database.
  """
  def migrate do
    init([:ssl])

    for repo <- repos() do
      {:ok, _fun_return, _apps} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  @doc """
  Seed the application.
  """
  # sobelow_skip ["RCE.CodeModule"]
  def seed do
    init([:crypto, :ssl, :postgrex, :ecto, :ecto_sql, :faker])

    Enum.each(repos(), & &1.start_link(pool_size: 1))

    [:code.priv_dir(@app), "repo", "seeds.exs"]
    |> Path.join()
    |> Code.eval_file()
  end

  @doc """
  Reset the application by dropping and recreating the public schema.
  """
  def reset do
    init([:ssl])

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn repo ->
          repo.query!("DROP SCHEMA public CASCADE")
          repo.query!("CREATE SCHEMA public")
        end)
    end

    migrate()
    seed()
  end
end
