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

    use Igniter.Mix.Task

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        adds_deps: [{:igniter_js, "~> 0.4.6", only: [:dev, :test]}],
        example: __MODULE__.Docs.example(),
        schema: [app_js_path: :string, yes: :boolean],
        defaults: [app_js_path: @default_app_js_path]
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      # Do your work here and return an updated igniter
      igniter
      |> Igniter.add_warning("mix backpex.install is not yet implemented")

      # TODO: Install Hooks in app.js
      # TODO: Add Backpex to dependencies in mix.exs
      # TODO: Add Backpex files to Tailwind content
      # TODO: Update formatter configuration
      # TODO: Create layout file
      # TODO: Remove background color from body tag
      # TODO: Configure daisyUI theme
      # TODO: Add ThemeSelectorPlug to pipeline
      # TODO: Remove @tailwindcss/forms plugin or switch to 'class' strategy
      # TODO: Set up Heroicons and Tailwind plugin for icons
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
