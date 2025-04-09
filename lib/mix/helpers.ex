defmodule Backpex.Mix.Helpers do
  @moduledoc """
  Helper functions for the Backpex mix tasks.
  """

  @doc """
  Gets the Phoenix PubSub module from the application configuration.
  """
  def pubsub_module(igniter) do
    web_module = Igniter.Libs.Phoenix.web_module(igniter)
    endpoint_module = Module.safe_concat(web_module, Endpoint)
    app_name = Igniter.Project.Application.app_name(igniter)

    Application.get_env(app_name, endpoint_module)[:pubsub_server]
  end

  @doc """
  Checks if a specific string exists within a module's source code.
  """
  def exists_in_module?(igniter, module, line) do
    case Igniter.Project.Module.find_module(igniter, module) do
      {:ok, {igniter, source, _zipper}} ->
        {:ok, {igniter, string_in_source?(source, line)}}

      {:error, igniter} ->
        Mix.shell().warning("Could not find module #{inspect(module)}")
        {:error, igniter}
    end
  end

  @doc """
  Checks if a specific string exists within a source's content.
  """
  def string_in_source?(source, string) do
    source
    |> Rewrite.Source.get(:content)
    |> String.contains?(string)
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
