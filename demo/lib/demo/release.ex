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
  def migrate(direction \\ :up) do
    init([:ssl])

    for repo <- repos() do
      {:ok, _fun_return, _apps} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, direction, all: true))
    end
  end

  @doc """
  Seed the application.
  """
  # sobelow_skip ["RCE.CodeModule"]
  def seed do
    init([:crypto, :ssl, :myxql, :ecto, :ecto_sql, :faker])

    Enum.each(repos(), & &1.start_link(pool_size: 1))

    [:code.priv_dir(@app), "repo", "seeds.exs"]
    |> Path.join()
    |> Code.eval_file()
  end

  @doc """
  Reset the application.
  """
  def reset do
    migrate(:down)
    migrate()
    seed()
  end
end
