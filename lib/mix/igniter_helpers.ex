if Code.ensure_loaded?(Igniter) do
  defmodule Backpex.Mix.IgniterHelpers do
    @moduledoc """
    Helper functions for the Backpex mix tasks.
    """

    alias Igniter.Libs.Phoenix
    alias Igniter.Project.Application, as: IgniterApp
    alias Igniter.Project.Module, as: IgniterModule
    alias Igniter.Util.Warning

    @doc """
    Gets the Phoenix PubSub module from the application configuration.

    Falls back to `MyApp.PubSub`, the module Phoenix generates, when the endpoint
    configuration is not loaded.
    """
    def pubsub_module(igniter) do
      web_module = Phoenix.web_module(igniter)
      endpoint_module = Module.safe_concat(web_module, Endpoint)
      app_name = IgniterApp.app_name(igniter)

      Application.get_env(app_name, endpoint_module)[:pubsub_server] ||
        IgniterModule.module_name(igniter, "PubSub")
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
        Warning.warn_with_code_sample(
          igniter,
          "File not found at #{file_path}. Please manually add the following line:",
          new_line
        )
      end
    end

    defp add_line(source, file_path, line) do
      content = Rewrite.Source.get(source, :content)

      if String.contains?(content, line) do
        Mix.shell().info("'#{line}' already exists in #{file_path}.")
        source
      else
        Rewrite.Source.update(source, :content, content <> "\n#{line}")
      end
    end

    @doc """
    Gets the web folder path for the Phoenix application, e.g. `lib/my_app_web`.
    """
    def web_folder_path(igniter) do
      web_module = Phoenix.web_module(igniter)

      igniter
      |> IgniterModule.proper_location(web_module)
      |> Path.rootname()
    end

    @doc """
    Checks if an npm package is already installed in the project.
    """
    def npm_package_installed?(package_name) do
      env = [{"PATH", System.get_env("PATH")}]

      case System.cmd("npm", ["list", "--depth=0", package_name], stderr_to_stdout: true, env: env) do
        {_output, 0} -> true
        {_output, _int} -> false
      end
    end
  end
end
