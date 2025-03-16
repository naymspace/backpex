defmodule Mix.Tasks.Backpex.Install.Docs do
  @moduledoc false

  def short_doc do
    "A short description of your task"
  end

  def example do
    "mix backpex.install --example arg"
  end

  def long_doc do
    """
    #{short_doc()}

    Longer explanation of your task

    ## Example

    ```bash
    #{example()}
    ```

    ## Options

    * `--example-option` or `-e` - Docs for your option
    """
  end
end

if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.Backpex.Install do
    @shortdoc "#{__MODULE__.Docs.short_doc()}"

    @moduledoc __MODULE__.Docs.long_doc()

    @default_app_js_path Path.join(["assets", "js", "app.js"])
    @default_app_css_path Path.join(["assets", "css", "app.css"])
    @hooks "...BackpexHooks"
    @imports "import { Hooks as BackpexHooks } from 'backpex';"

    use Igniter.Mix.Task

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        installs: [igniter_js: "~> 0.4.6"],
        example: __MODULE__.Docs.example(),
        schema: [app_js_path: :string, app_css_path: :string, yes: :boolean],
        defaults: [app_js_path: @default_app_js_path, app_css_path: @default_app_css_path]
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      pubsub_module = Igniter.Project.Module.module_name(igniter, "PubSub")

      igniter
      # |> Igniter.Project.Deps.add_dep({:igniter_js, "~> 0.4.6", only: [:dev, :test]})
      |> Igniter.Project.Formatter.import_dep(:backpex)
      |> Igniter.Project.Config.configure_new("config.exs", :backpex, [:pubsub_server], pubsub_module)
      |> add_backpex_routes()
      |> install_backpex_hooks()
      |> install_daisyui()
    end

    defp add_backpex_routes(igniter) do
      web_module = Igniter.Libs.Phoenix.web_module(igniter)

      case Igniter.Libs.Phoenix.select_router(igniter) do
        {igniter, nil} ->
          Mix.shell().error("Could not find router")
          igniter

        {igniter, router} ->
          igniter
          |> add_import_after_use(router, web_module, Backpex.Router)
          |> Igniter.Libs.Phoenix.add_scope("/", "backpex_routes()", arg2: web_module)
      end
    end

    defp add_import_after_use(igniter, target_module, use_module, import_module) do
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

    defp install_backpex_hooks(igniter) do
      app_js_path = igniter.args.options[:app_js_path]

      with {:ok, content} <- IgniterJs.Helpers.read_and_validate_file(app_js_path),
           {:ok, _, content} <- IgniterJs.Parsers.Javascript.Parser.insert_imports(content, @imports, :content),
           {:ok, _, content} <- IgniterJs.Parsers.Javascript.Parser.extend_hook_object(content, @hooks, :content) do
        Igniter.create_new_file(igniter, app_js_path, content, on_exists: :overwrite)
      else
        {:error, _function, error} -> Mix.raise("Failed to modify app.js: #{error}")
        {:error, error} -> Mix.raise("Could not read app.js: #{error}")
      end
    end

    defp install_daisyui(igniter) do
      with :ok <- install_daisyui_via_npm(),
           {:ok, igniter} <- add_daisyui_plugin_to_app_css(igniter) do
        Igniter.add_notice(igniter, "Installed daisyUI via npm.")
      else
        {:error, error} ->
          Igniter.Util.Warning.warn_with_code_sample(
            igniter,
            "Error installing daisyUI: #{inspect(error)}, please install daisyUI manually and add the following plugin to the app.css file:",
            "@plugin \"daisyui\";"
          )
      end
    end

    defp install_daisyui_via_npm do
      with true <- install_daisyui?(),
           {_version, 0} <- System.cmd("npm", ["--version"], stderr_to_stdout: true),
           {_output, 0} <- System.cmd("npm", ["i", "-D", "daisyui@latest"], stderr_to_stdout: true) do
        :ok
      else
        {error, _} -> {:error, error}
      end
    end

    defp install_daisyui? do
      Igniter.Util.IO.yes?(
        "The following npm package needs to be installed: `daisyui`. Do you want to install `daisyui@latest` via npm?"
      )
    end

    defp add_daisyui_plugin_to_app_css(igniter) do
      app_css_path = igniter.args.options[:app_css_path]

      if Igniter.exists?(igniter, app_css_path) do
        igniter =
          Igniter.update_file(igniter, app_css_path, fn source ->
            content = Rewrite.Source.get(source, :content)

            if String.contains?(content, "@plugin \"daisyui\";") do
              Mix.shell().info("daisyUI plugin already configured in app.css.")
              source
            else
              Rewrite.Source.update(source, :content, content <> "\n@plugin \"daisyui\";\n")
            end
          end)

        {:ok, igniter}
      else
        {:error, "app.css not found at #{app_css_path}."}
      end
    end
  end
else
  defmodule Mix.Tasks.Backpex.Install do
    @shortdoc "#{__MODULE__.Docs.short_doc()} | Install `igniter` to use"

    @moduledoc __MODULE__.Docs.long_doc()

    use Mix.Task

    def run(_argv) do
      Mix.shell().error("""
      The task 'backpex.install' requires igniter. Please install igniter and try again.

      For more information, see: https://hexdocs.pm/igniter/readme.html#installation
      """)

      exit({:shutdown, 1})
    end
  end
end
