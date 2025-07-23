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

    use Igniter.Mix.Task

    alias Backpex.Mix.Helpers

    alias Igniter.Code.Common
    alias Igniter.Libs.Phoenix
    alias Igniter.Project.Config
    alias Igniter.Project.Formatter
    alias Igniter.Project.Module
    alias Igniter.Util.IO, as: IgniterIO
    alias Igniter.Util.Warning
    alias IgniterJs.Parsers.Javascript.Parser

    @default_app_js_path Path.join(["assets", "js", "app.js"])
    @default_app_css_path Path.join(["assets", "css", "app.css"])
    @hooks "...BackpexHooks"
    @imports "import { Hooks as BackpexHooks } from 'backpex'"
    @daisyui_version "daisyui@5"

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        adds_deps: [igniter_js: "~> 0.4"],
        example: __MODULE__.Docs.example(),
        schema: [app_js_path: :string, app_css_path: :string, no_layout: :boolean],
        defaults: [app_js_path: @default_app_js_path, app_css_path: @default_app_css_path, no_layout: false]
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      igniter
      |> check_tailwind_version()
      |> configure_pubsub_server()
      |> install_backpex_hooks()
      |> install_daisyui()
      |> add_files_to_tailwind_content()
      |> add_backpex_formatter()
      |> add_backpex_routes()
      |> generate_layout()
      |> check_for_bg_white()
      |> check_for_tailwind_forms_plugin()
    end

    # Global configuration

    defp configure_pubsub_server(igniter) do
      pubsub_module = Helpers.pubsub_module(igniter)
      Config.configure_new(igniter, "config.exs", :backpex, [:pubsub_server], pubsub_module)
    end

    # Tailwind version check

    defp check_tailwind_version(igniter) do
      with version when is_binary(version) <- Application.get_env(:tailwind, :version),
           {true, _version} <- version_compatible?(version) do
        igniter
      else
        nil -> show_tailwind_warning(igniter, "no version found")
        {false, version} -> show_tailwind_warning(igniter, version)
      end
    end

    defp version_compatible?(version) do
      [major | _rest] = String.split(version, ".")
      {major_num, _remainder} = Integer.parse(major)
      {major_num >= 4, version}
    end

    defp show_tailwind_warning(igniter, version_info) do
      message =
        "No compatible Tailwind version found in config.exs (#{version_info}). Backpex requires Tailwind CSS >= 4.x.x. Do you want to continue anyway? Installation may not work correctly."

      if IgniterIO.yes?(message) do
        igniter
      else
        Mix.raise("Installation cancelled. Please install Tailwind CSS >= 4.x.x and try again.")
      end
    end

    # Backpex hooks

    defp install_backpex_hooks(igniter) do
      app_js_path = igniter.args.options[:app_js_path]

      with {:ok, content} <- IgniterJs.Helpers.read_and_validate_file(app_js_path),
           {:ok, _fun, content} <- Parser.insert_imports(content, @imports, :content),
           {:ok, _fun, content} <- Parser.extend_hook_object(content, @hooks, :content) do
        Igniter.create_new_file(igniter, app_js_path, content, on_exists: :overwrite)
      else
        {:error, _fun, error} -> Mix.raise("Failed to modify app.js: #{error}")
        {:error, error} -> Mix.raise("Could not read app.js: #{error}")
      end
    end

    # Install daisyUI

    defp install_daisyui(igniter) do
      app_css_path = igniter.args.options[:app_css_path]

      with false <- Igniter.exists?(igniter, "assets/vendor/daisyui.js"),
           false <- Helpers.npm_package_installed?(@daisyui_version),
           :ok <- install_daisyui_via_npm(),
           igniter <- Helpers.add_line_to_file(igniter, app_css_path, "@plugin \"daisyui\"") do
        Igniter.add_notice(igniter, "Installed daisyUI via npm.")
      else
        true ->
          Mix.shell().info("daisyui is already installed. Skipping.")
          igniter

        {:error, error} ->
          Warning.warn_with_code_sample(
            igniter,
            "Error installing daisyUI: #{inspect(error)}, please install daisyUI manually and add the following plugin to the app.css file:",
            "@plugin \"daisyui\""
          )
      end
    end

    defp install_daisyui_via_npm do
      cmd_opts = [stderr_to_stdout: true, env: [{"PATH", System.get_env("PATH")}]]

      with true <- install_daisyui?(),
           {_version, 0} <- System.cmd("npm", ["--version"], cmd_opts),
           {_output, 0} <- System.cmd("npm", ["i", "-D", @daisyui_version], cmd_opts) do
        :ok
      else
        false -> {:error, "Denied by user"}
        {error, _int} -> {:error, error}
      end
    end

    defp install_daisyui? do
      IgniterIO.yes?(
        "The following npm package is outdated or needs to be installed: '#{@daisyui_version}'. Do you want to install '#{@daisyui_version}' via npm?"
      )
    end

    # Add backpex files to tailwind content

    defp add_files_to_tailwind_content(igniter) do
      app_css_path = igniter.args.options[:app_css_path]

      igniter
      |> Helpers.add_line_to_file(app_css_path, "@source \"../../deps/backpex/**/*.*ex\"")
      |> Helpers.add_line_to_file(app_css_path, "@source \"../../deps/backpex/assets/js/**/*.*js\"")
    end

    # Add Backpex to formatter

    defp add_backpex_formatter(igniter) do
      Formatter.import_dep(igniter, :backpex)
    end

    # Add Backpex routes

    defp add_backpex_routes(igniter) do
      web_module = Phoenix.web_module(igniter)

      case Phoenix.select_router(igniter) do
        {igniter, nil} ->
          Mix.shell().error("Could not find router")
          igniter

        {igniter, router} ->
          with {:ok, {igniter, false}} <- Helpers.exists_in_module?(igniter, router, "import Backpex.Router"),
               {:ok, {igniter, false}} <- Helpers.exists_in_module?(igniter, router, "backpex_routes()"),
               {:ok, igniter} <-
                 Module.find_and_update_module(igniter, router, &add_backpex_router_import(&1, igniter)) do
            contents = """
            pipe_through :browser
            backpex_routes()
            """

            Phoenix.add_scope(igniter, "/", contents, arg2: web_module)
          else
            {:ok, {igniter, true}} ->
              Mix.shell().info("Backpex routes already added")
              igniter

            {:error, igniter} ->
              Mix.raise("Failed to add backpex routes")
              igniter
          end
      end
    end

    defp add_backpex_router_import(zipper, igniter) do
      case Phoenix.move_to_router_use(igniter, zipper) do
        {:ok, zipper} ->
          {:ok, Common.add_code(zipper, "import Backpex.Router")}

        _error ->
          Mix.shell().error(
            "Could not find router use. Please manually add the following line to your router: import Backpex.Router"
          )

          {:ok, zipper}
      end
    end

    # Creates default admin layout

    defp generate_layout(igniter) do
      if igniter.args.options[:no_layout] do
        Mix.shell().info("Skipping layout generation.")
        igniter
      else
        backpex_path = Application.app_dir(:backpex)
        web_folder_path = Helpers.web_folder_path(igniter)
        target_path = Path.join([web_folder_path, "components", "layouts", "admin.html.heex"])
        template_path = Path.join([backpex_path, "priv", "templates", "layouts", "admin.html.heex"])

        Igniter.copy_template(igniter, template_path, target_path, [], on_exists: :warning)
      end
    end

    # Checks for default background color

    defp check_for_bg_white(igniter) do
      web_folder_path = Helpers.web_folder_path(igniter)
      root_layout_path = Path.join([web_folder_path, "components", "layouts", "root.html.heex"])

      if Igniter.exists?(igniter, root_layout_path) do
        Igniter.update_file(igniter, root_layout_path, &maybe_remove_bg_white/1)
      else
        Igniter.add_warning(igniter, "root.html.heex not found at #{root_layout_path}")
      end
    end

    defp maybe_remove_bg_white(source) do
      root_layout_content = Rewrite.Source.get(source, :content)
      body_tag_with_bg_white = "<body class=\"bg-white\">"

      if String.contains?(root_layout_content, body_tag_with_bg_white) do
        if remove_bg_white?() do
          new_content = String.replace(root_layout_content, body_tag_with_bg_white, "<body>")
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

    # Checks for tailwind forms plugin

    defp check_for_tailwind_forms_plugin(igniter) do
      app_css_path = igniter.args.options[:app_css_path]
      line = "@plugin \"@tailwindcss/forms\""

      if Igniter.exists?(igniter, app_css_path) do
        Igniter.update_file(igniter, app_css_path, &maybe_remove_tailwind_forms_plugin(&1, line))
      else
        Warning.warn_with_code_sample(
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
        _false -> source
      end
    end

    defp remove_tailwind_forms_plugin?(line) do
      Mix.shell().yes?("The following line could cause issues with daisyUI: #{line}. Do you want to remove it?")
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
