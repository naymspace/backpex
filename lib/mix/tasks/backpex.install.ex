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
    - Adds [Backpex Hooks](installation.html#backpex-hooks) to your app.js or app.ts file (auto-detected)
    - Installs [daisyUI](installation.html#daisyui) via npm (with your permission)
    - Sets up the [formatter configuration](installation.html#setup-formatter)
    - Adds [Backpex files to Tailwind content](installation.html#add-files-to-tailwind-content)
    - Adds `import Backpex.Router`, `backpex_routes()` and a `live_session` with `Backpex.InitAssigns` to an `/admin` scope in your router
    - Creates a default admin layout
    - Checks for and offers to remove the [default background color](installation.html#remove-default-background-color)
    - Checks for and offers to remove the [@tailwindcss/forms plugin](installation.html#remove-tailwindcssforms-plugin)

    ## Example

    ```bash
    #{example()}
    ```

    ## Options

    * `--app-js-path` - Path to your app.js or app.ts file (auto-detected by default)
    * `--app-css-path` - Path to your app.css file (default: "assets/css/app.css")
    * `--no-layout` - Skip generating the admin layout
    * `--yes` - Answer all confirmation prompts with yes (also applied when no TTY is attached, e.g. in CI)
    """
  end
end

if Code.ensure_loaded?(Igniter) and Code.ensure_loaded?(IgniterJs) do
  defmodule Mix.Tasks.Backpex.Install do
    @shortdoc "#{__MODULE__.Docs.short_doc()}"
    @moduledoc __MODULE__.Docs.long_doc()

    use Igniter.Mix.Task

    alias Backpex.Mix.IgniterHelpers
    alias Igniter.Code.Common
    alias Igniter.Libs.Phoenix
    alias Igniter.Mix.Task.Info
    alias Igniter.Project.Config
    alias Igniter.Project.Formatter
    alias Igniter.Project.Module
    alias Igniter.Util.IO, as: IgniterIO
    alias Igniter.Util.Warning
    alias IgniterJs.Parsers.Javascript.Parser

    @default_app_css_path Path.join(["assets", "css", "app.css"])
    @hooks "...BackpexHooks"
    @imports "import { Hooks as BackpexHooks, backpexParams } from 'backpex'"
    @daisyui_version "daisyui@5"
    @admin_scope "/admin"
    @live_session String.trim_trailing("""
                  live_session :backpex_admin, on_mount: Backpex.InitAssigns do
                    # live_resources "/posts", PostLive
                  end
                  """)

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Info{
        adds_deps: [igniter_js: "~> 0.4"],
        example: __MODULE__.Docs.example(),
        schema: [app_js_path: :string, app_css_path: :string, no_layout: :boolean],
        defaults: [app_js_path: nil, app_css_path: @default_app_css_path, no_layout: false]
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
      pubsub_module = IgniterHelpers.pubsub_module(igniter)
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

      if yes?(igniter, message) do
        igniter
      else
        Mix.raise("Installation cancelled. Please install Tailwind CSS >= 4.x.x and try again.")
      end
    end

    # Backpex hooks

    defp install_backpex_hooks(igniter) do
      app_js_path = igniter.args.options[:app_js_path] || detect_app_file_path(igniter)

      if Igniter.exists?(igniter, app_js_path) do
        igniter
        |> Igniter.update_file(app_js_path, &add_backpex_hooks(&1, app_js_path))
        |> Igniter.add_notice("""
        Wrap your LiveSocket connect params with backpexParams in #{app_js_path}:

            #{@imports}

            const liveSocket = new LiveSocket('/live', Socket, {
              params: backpexParams({ _csrf_token: csrfToken }),
              hooks: { ...BackpexHooks }
            })

        Without it, preferences written after the websocket connects (hidden
        columns, hidden metrics) reappear on the next live navigation.
        """)
      else
        warn_manual_hooks(igniter, "Could not find #{app_js_path}.")
      end
    end

    defp add_backpex_hooks(source, app_js_path) do
      content = Rewrite.Source.get(source, :content)

      with {:ok, new_content} <- maybe_insert_backpex_imports(content),
           {:ok, new_content} <- maybe_extend_hook_object(new_content) do
        if new_content == content, do: source, else: Rewrite.Source.update(source, :content, new_content)
      else
        {:error, _fun, error} ->
          {:warning, manual_hooks_warning("Failed to modify #{app_js_path}: #{inspect(error)}")}
      end
    end

    # igniter_js reformats the whole file and its import dedupe differs between versions,
    # so only call it when the import or hook is actually missing.
    defp maybe_insert_backpex_imports(content) do
      if Regex.match?(~r/from\s*["']backpex["']/, content) do
        {:ok, content}
      else
        with {:ok, _fun, content} <- Parser.insert_imports(content, @imports, :content), do: {:ok, content}
      end
    end

    defp maybe_extend_hook_object(content) do
      if String.contains?(content, @hooks) do
        {:ok, content}
      else
        with {:ok, _fun, content} <- Parser.extend_hook_object(content, @hooks, :content), do: {:ok, content}
      end
    end

    defp warn_manual_hooks(igniter, reason) do
      Igniter.add_warning(igniter, manual_hooks_warning(reason))
    end

    # Warning.formatted_warning/2 runs the sample through the Elixir formatter, so build the JS sample by hand.
    defp manual_hooks_warning(reason) do
      """
      #{reason} Please add the Backpex hooks to your app.js manually:

          #{@imports}

          const liveSocket = new LiveSocket('/live', Socket, {
            params: backpexParams({ _csrf_token: csrfToken }),
            hooks: { #{@hooks} }
          })
      """
    end

    # Auto-detect app.js or app.ts file

    defp detect_app_file_path(igniter) do
      js_path = Path.join(["assets", "js", "app.js"])
      ts_path = Path.join(["assets", "js", "app.ts"])

      cond do
        Igniter.exists?(igniter, ts_path) ->
          Mix.shell().info("Detected TypeScript app file: #{ts_path}")
          ts_path

        Igniter.exists?(igniter, js_path) ->
          Mix.shell().info("Detected JavaScript app file: #{js_path}")
          js_path

        true ->
          Mix.shell().info("No app.js or app.ts found, defaulting to: #{js_path}")
          js_path
      end
    end

    # Install daisyUI

    defp install_daisyui(igniter) do
      app_css_path = igniter.args.options[:app_css_path]

      with false <- Igniter.exists?(igniter, "assets/vendor/daisyui.js"),
           false <- IgniterHelpers.npm_package_installed?(@daisyui_version),
           :ok <- install_daisyui_via_npm(igniter) do
        igniter = IgniterHelpers.add_line_to_file(igniter, app_css_path, "@plugin \"daisyui\"")
        Igniter.add_notice(igniter, "Installed daisyUI via npm.")
      else
        true ->
          Mix.shell().info("daisyUI is already installed. Skipping.")
          igniter

        {:error, error} ->
          Warning.warn_with_code_sample(
            igniter,
            "Error installing daisyUI: #{inspect(error)}, please install daisyUI manually and add the following plugin to the app.css file:",
            "@plugin \"daisyui\""
          )
      end
    end

    defp install_daisyui_via_npm(igniter) do
      cmd_opts = [stderr_to_stdout: true, env: [{"PATH", System.get_env("PATH")}]]

      with true <- install_daisyui?(igniter),
           {_version, 0} <- System.cmd("npm", ["--version"], cmd_opts),
           {_output, 0} <- System.cmd("npm", ["i", "-D", @daisyui_version], cmd_opts) do
        :ok
      else
        false -> {:error, "Denied by user"}
        {error, _int} -> {:error, error}
      end
    end

    defp install_daisyui?(igniter) do
      yes?(
        igniter,
        "The following npm package is outdated or needs to be installed: '#{@daisyui_version}'. Do you want to install '#{@daisyui_version}' via npm?"
      )
    end

    # Add backpex files to tailwind content

    defp add_files_to_tailwind_content(igniter) do
      app_css_path = igniter.args.options[:app_css_path]

      igniter
      |> IgniterHelpers.add_line_to_file(app_css_path, "@source \"../../deps/backpex/**/*.*ex\";")
      |> IgniterHelpers.add_line_to_file(app_css_path, "@source \"../../deps/backpex/assets/js/**/*.*js\";")
    end

    # Add Backpex to formatter

    defp add_backpex_formatter(igniter) do
      Formatter.import_dep(igniter, :backpex)
    end

    # Add Backpex routes

    defp add_backpex_routes(igniter) do
      web_module = Phoenix.web_module(igniter)

      case Phoenix.select_router(igniter) do
        {igniter, nil} -> warn_manual_routes(igniter, web_module)
        {igniter, router} -> add_backpex_routes(igniter, router, web_module)
      end
    end

    defp add_backpex_routes(igniter, router, web_module) do
      case Module.find_module(igniter, router) do
        {:ok, {igniter, source, zipper}} ->
          import? = IgniterHelpers.string_in_source?(source, "import Backpex.Router")
          routes? = IgniterHelpers.string_in_source?(source, "backpex_routes()")
          init_assigns? = IgniterHelpers.string_in_source?(source, "Backpex.InitAssigns")

          cond do
            import? and routes? and init_assigns? ->
              Mix.shell().info("Backpex routes already added")
              igniter

            # Without the import the scope would not compile, so leave the router alone.
            not import? and not router_use?(igniter, zipper) ->
              warn_manual_routes(igniter, web_module)

            true ->
              igniter
              |> maybe_add_backpex_router_import(router, import?)
              |> add_backpex_scope(router, web_module, routes?, init_assigns?)
          end

        {:error, igniter} ->
          warn_manual_routes(igniter, web_module)
      end
    end

    defp router_use?(igniter, zipper) do
      match?({:ok, _zipper}, Phoenix.move_to_router_use(igniter, zipper))
    end

    defp maybe_add_backpex_router_import(igniter, _router, true = _import?), do: igniter

    defp maybe_add_backpex_router_import(igniter, router, false = _import?) do
      Module.find_and_update_module!(igniter, router, fn zipper ->
        {:ok, zipper} = Phoenix.move_to_router_use(igniter, zipper)
        {:ok, Common.add_code(zipper, "import Backpex.Router")}
      end)
    end

    defp add_backpex_scope(igniter, router, web_module, routes?, init_assigns?) do
      contents =
        for {present?, code} <- [{routes?, "backpex_routes()"}, {init_assigns?, @live_session}],
            not present?,
            into: "",
            do: code <> "\n"

      igniter
      |> Phoenix.append_to_scope(@admin_scope, contents, router: router, arg2: web_module, with_pipelines: [:browser])
      |> maybe_add_live_session_notice(init_assigns?)
    end

    defp maybe_add_live_session_notice(igniter, true = _init_assigns?), do: igniter

    defp maybe_add_live_session_notice(igniter, false = _init_assigns?) do
      Igniter.add_notice(igniter, """
      Backpex added a `live_session` with `on_mount: Backpex.InitAssigns` to the
      #{inspect(@admin_scope)} scope of your router. Add your LiveResources inside it:

          live_session :backpex_admin, on_mount: Backpex.InitAssigns do
            live_resources "/posts", PostLive
          end

      If the scope needs authentication or tenant hooks, list them before
      Backpex.InitAssigns so it can read the user and tenant from the assigns:

          on_mount: [{MyAppWeb.UserAuth, :require_authenticated}, Backpex.InitAssigns]

      Put backpex_routes() behind the same authentication pipelines.
      """)
    end

    defp warn_manual_routes(igniter, web_module) do
      Warning.warn_with_code_sample(
        igniter,
        """
        Failed to add backpex routes automatically. Please manually add the following to your router.ex:

        1. Add the import at the top of your router file:
        """,
        "import Backpex.Router"
      )
      |> Warning.warn_with_code_sample(
        """
        2. Add the backpex routes and a live_session with Backpex.InitAssigns in a scope with the browser pipeline:
        """,
        """
        scope #{inspect(@admin_scope)}, #{inspect(web_module)} do
          pipe_through :browser

          backpex_routes()

          #{String.replace(@live_session, "\n", "\n  ")}
        end
        """
      )
    end

    # Creates default admin layout

    defp generate_layout(igniter) do
      if igniter.args.options[:no_layout] do
        Mix.shell().info("Skipping layout generation.")
        igniter
      else
        backpex_path = Application.app_dir(:backpex)
        web_folder_path = IgniterHelpers.web_folder_path(igniter)
        target_path = Path.join([web_folder_path, "components", "layouts", "admin.html.heex"])
        template_path = Path.join([backpex_path, "priv", "templates", "layouts", "admin.html.heex"])

        Igniter.copy_template(igniter, template_path, target_path, [], on_exists: :warning)
      end
    end

    # Checks for default background color

    defp check_for_bg_white(igniter) do
      web_folder_path = IgniterHelpers.web_folder_path(igniter)
      root_layout_path = Path.join([web_folder_path, "components", "layouts", "root.html.heex"])

      if Igniter.exists?(igniter, root_layout_path) do
        Igniter.update_file(igniter, root_layout_path, &maybe_remove_bg_white(&1, igniter))
      else
        Igniter.add_warning(igniter, "root.html.heex not found at #{root_layout_path}")
      end
    end

    defp maybe_remove_bg_white(source, igniter) do
      root_layout_content = Rewrite.Source.get(source, :content)
      body_tag_with_bg_white = "<body class=\"bg-white\">"

      if String.contains?(root_layout_content, body_tag_with_bg_white) do
        if remove_bg_white?(igniter) do
          new_content = String.replace(root_layout_content, body_tag_with_bg_white, "<body>")
          Rewrite.Source.update(source, :content, new_content)
        else
          source
        end
      else
        source
      end
    end

    defp remove_bg_white?(igniter) do
      yes?(
        igniter,
        "A background color at the body could cause issues with the backpex app_shell component. Do you want to remove it? See: https://hexdocs.pm/backpex/installation.html#remove-default-background-color"
      )
    end

    # Checks for tailwind forms plugin

    defp check_for_tailwind_forms_plugin(igniter) do
      app_css_path = igniter.args.options[:app_css_path]
      line = "@plugin \"@tailwindcss/forms\""

      if Igniter.exists?(igniter, app_css_path) do
        Igniter.update_file(igniter, app_css_path, &maybe_remove_tailwind_forms_plugin(&1, line, igniter))
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

    defp maybe_remove_tailwind_forms_plugin(source, line, igniter) do
      app_css_content = Rewrite.Source.get(source, :content)

      with true <- String.contains?(app_css_content, line),
           true <- remove_tailwind_forms_plugin?(igniter, line) do
        Rewrite.Source.update(source, :content, &String.replace(&1, line, ""))
      else
        _false -> source
      end
    end

    defp remove_tailwind_forms_plugin?(igniter, line) do
      yes?(igniter, "The following line could cause issues with daisyUI: #{line}. Do you want to remove it?")
    end

    defp yes?(igniter, message) do
      igniter.args.options[:yes] || IgniterIO.yes?(message)
    end
  end
else
  defmodule Mix.Tasks.Backpex.Install do
    @shortdoc "#{__MODULE__.Docs.short_doc()} | Install `igniter` and `igniter_js` to use"

    @moduledoc __MODULE__.Docs.long_doc()

    use Mix.Task

    def run(_argv) do
      Mix.shell().error("""
      The task 'backpex.install' requires igniter and igniter_js. Please install igniter and try again.

      For more information, see: https://hexdocs.pm/igniter/readme.html#installation
      """)

      exit({:shutdown, 1})
    end
  end
end
