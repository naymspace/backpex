defmodule Mix.Tasks.Backpex.Install.Docs do
  @moduledoc false

  def short_doc do
    "Installs and sets up Backpex according to the installation guide"
  end

  def example do
    "mix backpex.install"
  end

  def long_doc do
    """
    #{short_doc()}

    This task automates the steps from the [Backpex installation guide](installation.html) to quickly set up Backpex in your Phoenix application.

    You can run it with `mix backpex.install` after adding Backpex to your dependencies,
    or with `mix igniter.install backpex` to add the dependency and run the installer in one step.

    ## What this installer does:

    - Sets up [Global Configuration](installation.html#global-configuration) by configuring the PubSub server
    - Adds [Backpex Hooks](installation.html#backpex-hooks) to your app.js file
    - Installs [daisyUI](installation.html#daisyui) via npm (with your permission)
    - Sets up the [formatter configuration](installation.html#setup-formatter)
    - Adds [Backpex files to Tailwind content](installation.html#add-files-to-tailwind-content)
    - Adds routes to your router
    - Creates a default admin layout
    - Checks for and offers to remove the [default background color](installation.html#remove-default-background-color)
    - Checks for and offers to remove the [@tailwindcss/forms plugin](installation.html#remove-tailwindcssforms-plugin)

    ## Example

    ```bash
    #{example()}
    ```

    ## Options

    * `--app-js-path` - Path to your app.js file (default: "assets/js/app.js")
    * `--app-css-path` - Path to your app.css file (default: "assets/css/app.css")
    * `--no-layout` - Skip generating the admin layout
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
    @imports "import { Hooks as BackpexHooks } from 'backpex'"

    use Igniter.Mix.Task

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        installs: [igniter_js: "~> 0.4.6"],
        example: __MODULE__.Docs.example(),
        schema: [app_js_path: :string, app_css_path: :string, no_layout: :boolean],
        defaults: [app_js_path: @default_app_js_path, app_css_path: @default_app_css_path, no_layout: false]
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      pubsub_module = Igniter.Project.Module.module_name(igniter, "PubSub")

      igniter
      |> Igniter.Project.Config.configure_new("config.exs", :backpex, [:pubsub_server], pubsub_module)
      |> install_backpex_hooks()
      |> install_daisyui()
      |> Igniter.Project.Formatter.import_dep(:backpex)
      |> add_files_to_tailwind_content()
      |> add_backpex_routes()
      |> generate_layout()
      |> check_for_bg_white()
      |> check_for_tailwind_forms_plugin()
    end

    # backpex hooks installation

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

    # daisyui installation

    defp install_daisyui(igniter) do
      with :ok <- install_daisyui_via_npm(),
           igniter <- update_app_css(igniter, "@plugin \"daisyui\"") do
        Igniter.add_notice(igniter, "Installed daisyUI via npm.")
      else
        {:error, error} ->
          Igniter.Util.Warning.warn_with_code_sample(
            igniter,
            "Error installing daisyUI: #{inspect(error)}, please install daisyUI manually and add the following plugin to the app.css file:",
            "@plugin \"daisyui\""
          )
      end
    end

    defp install_daisyui_via_npm do
      with true <- install_daisyui?(),
           {_version, 0} <- System.cmd("npm", ["--version"], stderr_to_stdout: true),
           {_output, 0} <- System.cmd("npm", ["i", "-D", "daisyui@latest"], stderr_to_stdout: true) do
        :ok
      else
        false -> {:error, "Denied by user"}
        {error, _} -> {:error, error}
      end
    end

    defp install_daisyui? do
      Igniter.Util.IO.yes?(
        "The following npm package needs to be installed: `daisyui`. Do you want to install `daisyui@latest` via npm?"
      )
    end

    # add backpex paths to app.css

    defp add_files_to_tailwind_content(igniter) do
      igniter
      |> update_app_css("@source \"../../deps/backpex/**/*.*ex\"")
      |> update_app_css("@source \"../../deps/backpex/assets/js/**/*.*js\"")
    end

    defp update_app_css(igniter, new_line) do
      app_css_path = igniter.args.options[:app_css_path]

      if Igniter.exists?(igniter, app_css_path) do
        Igniter.update_file(igniter, app_css_path, &add_line(&1, new_line))
      else
        Igniter.Util.Warning.warn_with_code_sample(
          igniter,
          "app.css not found at #{app_css_path}. Please manually add the following line to your app.css file:",
          new_line
        )
      end
    end

    defp add_line(source, line) do
      app_css_content = Rewrite.Source.get(source, :content)

      if String.contains?(app_css_content, line) do
        Mix.shell().info("#{line} already exists in app.css.")
        source
      else
        Rewrite.Source.update(source, :content, app_css_content <> "\n#{line}")
      end
    end

    # check for tailwind forms plugin

    defp check_for_tailwind_forms_plugin(igniter) do
      app_css_path = igniter.args.options[:app_css_path]
      line = "@plugin \"tailwindcss/forms\""

      if Igniter.exists?(igniter, app_css_path) do
        Igniter.update_file(igniter, app_css_path, &maybe_remove_tailwind_forms_plugin(&1, line))
      else
        Igniter.Util.Warning.warn_with_code_sample(
          igniter,
          """
          app.css not found at #{app_css_path}.
          You may remove the following line from your app.css file because it can cause issues with daisyUI:
          """,
          line
        )
      end
    end

    defp maybe_remove_tailwind_forms_plugin(source, line) do
      app_css_content = Rewrite.Source.get(source, :content)

      with true <- String.contains?(app_css_content, line),
           true <- remove_tailwind_forms_plugin?(line) do
        Rewrite.Source.update(source, :content, &String.replace(&1, line, ""))
      else
        _ -> source
      end
    end

    defp remove_tailwind_forms_plugin?(line) do
      Mix.shell().yes?("The following line could cause issues with daisyUI: #{line}. Do you want to remove it?")
    end

    # check for "bg-white"

    defp check_for_bg_white(igniter) do
      root_layout_path = Path.join([web_folder_path(igniter), "components", "layouts", "root.html.heex"])

      if Igniter.exists?(igniter, root_layout_path) do
        Igniter.update_file(igniter, root_layout_path, &maybe_remove_bg_white/1)
      else
        Igniter.add_warning(igniter, "root.html.heex not found at #{root_layout_path}")
      end
    end

    defp maybe_remove_bg_white(source) do
      root_layout_content = Rewrite.Source.get(source, :content)
      body_tag_with_bg_white = "<body class=\"h-full bg-white\">"

      if String.contains?(root_layout_content, body_tag_with_bg_white) do
        if remove_bg_white?() do
          new_content = String.replace(root_layout_content, body_tag_with_bg_white, "<body class=\"h-full\">")
          Rewrite.Source.update(source, :content, new_content)
        else
          source
        end
      else
        source
      end
    end

    defp remove_bg_white? do
      Mix.shell().yes?(
        "A background color at the body could cause issues with the backpex app_shell. Do you want to remove it? See: https://hexdocs.pm/backpex/installation.html#remove-default-background-color"
      )
    end

    # admin layout generation

    defp generate_layout(igniter) do
      if igniter.args.options[:no_layout] do
        Mix.shell().info("Skipping layout generation.")
        igniter
      else
        backpex_path = Application.app_dir(:backpex)
        web_folder_path = web_folder_path(igniter)
        target_path = Path.join([web_folder_path, "components", "layouts", "admin.html.heex"])
        template_path = Path.join([backpex_path, "priv", "templates", "layouts", "admin.html.heex"])

        Igniter.copy_template(igniter, template_path, target_path, [], on_exists: :warning)
      end
    end

    defp web_folder_path(igniter) do
      igniter
      |> Igniter.Project.Application.app_name()
      |> Mix.Phoenix.web_path()
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
