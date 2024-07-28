defmodule Mix.Tasks.Bpx.Gen.Live do
  @shortdoc "Generates LiveView, templates, and context for a resource"

  use Mix.Task

  alias Mix.Backpex.LiveResource

  @doc false
  def run(args) do
    if Mix.Project.umbrella?() do
      Mix.raise("mix bpx.gen.live must be invoked from within your *_web application root directory")
    end

    Mix.Task.run("compile")
    live_resource = build(args)

    paths = [".", :backpex]

    live_resource
    |> copy_new_files(paths, live_resource: live_resource)
  end

  def build(args) do
    {opts, [schema], _} = OptionParser.parse(args, strict: [file: :string])

    LiveResource.new(schema, opts)
  end

  @doc false
  defp files_to_be_generated(file) do
    web_prefix = Mix.Phoenix.web_path(Mix.Phoenix.otp_app())
    web_live = Path.join([web_prefix, "live", file])
    [{:eex, "live_resource.ex", web_live}]
  end

  defp copy_new_files(%LiveResource{} = live_resource, paths, binding) do
    files = files_to_be_generated(live_resource.file)

    Mix.Phoenix.copy_from(paths, "priv/templates/bpx.gen.live", binding, files)

    live_resource
  end
end
