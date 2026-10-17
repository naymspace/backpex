defmodule Mix.Tasks.Backpex.InstallTest do
  # Not async: the setup changes the working directory and the Mix shell.
  use ExUnit.Case, async: false

  import Igniter.Test

  @app_js "assets/js/app.js"
  @app_css "assets/css/app.css"
  @router "lib/test_web/router.ex"
  @root_layout "lib/test_web/components/layouts/root.html.heex"

  setup do
    # Igniter matches its in-memory test files with globs against absolute paths and `**`
    # skips dot directories, so the tests fail inside a checkout below e.g. `.claude/worktrees`.
    cwd = File.cwd!()
    File.cd!(System.tmp_dir!())
    Mix.shell(Mix.Shell.Process)

    on_exit(fn ->
      File.cd!(cwd)
      Mix.shell(Mix.Shell.IO)
    end)
  end

  describe "fresh install" do
    setup do
      %{igniter: project() |> install() |> apply_igniter!()}
    end

    test "adds the router import, backpex_routes and a live_session with InitAssigns", %{igniter: igniter} do
      router = read(igniter, @router)

      assert count(router, "import Backpex.Router") == 1
      assert router =~ ~r/scope "\/admin", TestWeb do\s+pipe_through \[:browser\]\s+backpex_routes\(\)/
      assert router =~ "live_session :backpex_admin, on_mount: Backpex.InitAssigns do"
    end

    test "adds the Backpex hooks to app.js", %{igniter: igniter} do
      app_js = read(igniter, @app_js)

      assert count(app_js, "import { Hooks as BackpexHooks, backpexParams } from 'backpex'") == 1
      assert count(app_js, "...BackpexHooks") == 1
      assert app_js =~ "...colocatedHooks"
    end

    test "configures the pubsub server, formatter and tailwind sources", %{igniter: igniter} do
      assert read(igniter, "config/config.exs") =~ "config :backpex, pubsub_server: Test.PubSub"
      assert read(igniter, ".formatter.exs") =~ ":backpex"

      app_css = read(igniter, @app_css)
      assert app_css =~ ~s(@source "../../deps/backpex/**/*.*ex";)
      assert app_css =~ ~s(@source "../../deps/backpex/assets/js/**/*.*js";)
    end

    test "creates the admin layout in the web folder", %{igniter: igniter} do
      assert read(igniter, "lib/test_web/components/layouts/admin.html.heex") =~ "Backpex.HTML.Layout.app_shell"
    end

    test "re-running the installer changes nothing", %{igniter: igniter} do
      igniter
      |> install()
      |> assert_unchanged()
    end
  end

  describe "router" do
    test "adds backpex_routes and the live_session when only the import exists" do
      project()
      |> update_router(&String.replace(&1, "use TestWeb, :router", "use TestWeb, :router\n\n  import Backpex.Router"))
      |> install()
      |> apply_igniter!()
      |> read(@router)
      |> then(fn router ->
        assert count(router, "import Backpex.Router") == 1
        assert count(router, "backpex_routes()") == 1
        assert count(router, "Backpex.InitAssigns") == 1
      end)
    end

    test "adds only the live_session when the router already has the import and backpex_routes" do
      project()
      |> update_router(fn content ->
        content
        |> String.replace("use TestWeb, :router", "use TestWeb, :router\n\n  import Backpex.Router")
        |> String.replace(
          ~s/get("\/", PageController, :home)/,
          ~s/get("\/", PageController, :home)\n    backpex_routes()/
        )
      end)
      |> install()
      |> apply_igniter!()
      |> read(@router)
      |> then(fn router ->
        assert count(router, "import Backpex.Router") == 1
        assert count(router, "backpex_routes()") == 1
        assert router =~ ~r/scope "\/admin", TestWeb do\s+pipe_through \[:browser\]\s+live_session :backpex_admin/
      end)
    end
  end

  describe "app.js" do
    test "keeps earlier in-memory edits" do
      project()
      |> Igniter.update_file(@app_js, fn source ->
        Rewrite.Source.update(source, :content, &(~s/import "..\/vendor\/custom";\n/ <> &1))
      end)
      |> install()
      |> apply_igniter!()
      |> read(@app_js)
      |> then(fn app_js ->
        assert app_js =~ ~s/import "..\/vendor\/custom";/
        assert app_js =~ "...BackpexHooks"
      end)
    end

    test "leaves an existing Backpex import and hook untouched" do
      project()
      |> Igniter.update_file(@app_js, fn source ->
        Rewrite.Source.update(source, :content, fn content ->
          content
          |> String.replace(
            ~s/import topbar from "..\/vendor\/topbar"/,
            ~s/import topbar from "..\/vendor\/topbar"\nimport {Hooks as BackpexHooks, backpexParams} from "backpex"/
          )
          |> String.replace("hooks: {...colocatedHooks}", "hooks: {...colocatedHooks, ...BackpexHooks}")
        end)
      end)
      |> apply_igniter!()
      |> install()
      |> assert_unchanged(@app_js)
    end

    test "warns instead of raising when the file is missing" do
      project()
      |> Igniter.rm(@app_js)
      |> apply_igniter!()
      |> install()
      |> assert_has_warning(&(&1 =~ "Could not find #{@app_js}."))
    end
  end

  describe "--yes" do
    test "removes the body background color and the tailwind forms plugin without prompting" do
      igniter =
        project()
        |> Igniter.update_file(@root_layout, fn source ->
          Rewrite.Source.update(source, :content, &String.replace(&1, "<body>", ~s(<body class="bg-white">)))
        end)
        |> Igniter.update_file(@app_css, fn source ->
          Rewrite.Source.update(source, :content, &(&1 <> ~s(\n@plugin "@tailwindcss/forms";\n)))
        end)
        |> apply_igniter!()
        |> install()
        |> apply_igniter!()

      refute read(igniter, @root_layout) =~ "bg-white"
      refute read(igniter, @app_css) =~ "@tailwindcss/forms"
    end
  end

  # Vendoring daisyUI keeps the installer from running `npm install`.
  defp project do
    phx_test_project()
    |> Igniter.create_new_file("assets/vendor/daisyui.js", "")
    |> apply_igniter!()
  end

  defp install(igniter), do: Igniter.compose_task(igniter, "backpex.install", ["--yes"])

  defp update_router(igniter, fun) do
    igniter
    |> Igniter.update_file(@router, &Rewrite.Source.update(&1, :content, fun))
    |> apply_igniter!()
  end

  defp read(igniter, path) do
    igniter
    |> Igniter.include_existing_file(path)
    |> Map.fetch!(:rewrite)
    |> Rewrite.source!(path)
    |> Rewrite.Source.get(:content)
  end

  defp count(content, pattern), do: length(String.split(content, pattern)) - 1
end
