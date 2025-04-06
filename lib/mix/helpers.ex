defmodule Backpex.Mix.Helpers do
  @moduledoc """
  Helper functions for the Backpex mix tasks.
  """

  @doc """
  Gets the Phoenix PubSub module from the application configuration.
  """
  def pubsub_module(igniter) do
    web_module = Igniter.Libs.Phoenix.web_module(igniter)
    endpoint_module = Module.concat(web_module, Endpoint)
    app_name = Igniter.Project.Application.app_name(igniter)

    Application.get_env(app_name, endpoint_module)[:pubsub_server]
  end

  @doc """
  Adds an import statement after a specific module use statement.
  """
  def add_import_after_use(igniter, target_module, use_module, import_module) do
    Igniter.Project.Module.find_and_update_module!(
      igniter,
      target_module,
      fn zipper ->
        case Igniter.Code.Module.move_to_use(zipper, use_module) do
          {:ok, use_zipper} ->
            {:ok, Igniter.Code.Common.add_code(use_zipper, "import #{inspect(import_module)}")}

          _ ->
            Mix.shell().error("Could not find use module #{inspect(use_module)} in #{inspect(target_module)}")
            {:ok, zipper}
        end
      end
    )
  end

  @doc """
  Updates a file by adding a line if it doesn't already exist.
  """
  def add_line_to_file(igniter, file_path, new_line) do
    if Igniter.exists?(igniter, file_path) do
      Igniter.update_file(igniter, file_path, &add_line(&1, file_path, new_line))
    else
      Igniter.Util.Warning.warn_with_code_sample(
        igniter,
        "File not found at #{file_path}. Please manually add the following line:",
        new_line
      )
    end
  end

  defp add_line(source, file_path, line) do
    content = Rewrite.Source.get(source, :content)

    if String.contains?(content, line) do
      Mix.shell().info("#{line} already exists in #{file_path}.")
      source
    else
      Rewrite.Source.update(source, :content, content <> "\n#{line}")
    end
  end

  @doc """
  Gets the web folder path for the Phoenix application.
  """
  def web_folder_path(igniter) do
    igniter
    |> Igniter.Project.Application.app_name()
    |> Mix.Phoenix.web_path()
  end
end
