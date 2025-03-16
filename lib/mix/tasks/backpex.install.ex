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
    @hooks "...BackpexHooks"
    @imports "import { Hooks as BackpexHooks } from 'backpex';"

    use Igniter.Mix.Task

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        adds_deps: [igniter_js: "~> 0.4.6"],
        example: __MODULE__.Docs.example(),
        schema: [app_js_path: :string, yes: :boolean],
        defaults: [app_js_path: @default_app_js_path]
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      pubsub_module = Igniter.Project.Module.module_name(igniter, "PubSub")

      igniter
      |> Igniter.Project.Deps.add_dep({:igniter_js, "~> 0.4.6", only: [:dev, :test]})
      |> Igniter.Project.Formatter.import_dep(:backpex)
      |> Igniter.Project.Config.configure_new("config.exs", :backpex, [:pubsub_server], pubsub_module)
      |> add_backpex_routes()
      |> install_backpex_hooks()
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
