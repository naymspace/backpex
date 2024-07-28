defmodule Mix.Tasks.Bpx.Gen.Live do
  @shortdoc "Generates a Backpex.LiveResource for an existing ecto schema"

  @moduledoc """
  Generates a Backpex.LiveResource for an existing ecto schema.

      mix bpx.gen.live Demo.User --file "user_live"

  The first argument is the ecto schema module.
  It takes the field names and types of this schema to generate a Backpex.LiveResource.
  It has the minimum required code to display the `:index`, `:show`, `:new` and `:edit`.

  The second argument defines the name for the LiveView file and its module name.
  It will be copied to your projects `projectname_web/live` folder.


  This generator will add the following file:

    * a live_resource in `lib/app_web/live/user_live.ex`

  After file generation is complete, there will be output regarding required
  updates to the `lib/app_web/router.ex` file.

      Add the live routes to your browser scope in lib/app_web/router.ex:

      backpex_routes()

      live_session :default, on_mount: [Backpex.InitAssigns] do
        live_resources "/users", UserLive
      end
  """

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
