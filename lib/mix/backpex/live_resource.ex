defmodule Mix.Backpex.LiveResource do
  @moduledoc false

  alias Mix.Backpex.LiveResource

  defstruct module: nil,
            file: nil,
            repo: nil,
            layout: nil,
            schema: nil,
            pubsub: nil,
            topic: nil,
            event_prefix: nil,
            singular_name: nil,
            plural_name: nil,
            fields: []

  def new(schema_name, opts) do
    otp_app = Mix.Phoenix.otp_app()
    project_module = otp_app |> Atom.to_string() |> Phoenix.Naming.camelize()
    otp_web_module = (project_module <> "_web") |> Phoenix.Naming.camelize()
    module = Module.concat([otp_web_module, Phoenix.Naming.camelize(opts[:file])])
    repo = opts[:repo] || Module.concat([project_module, "Repo"])
    file = opts[:file] <> ".ex"
    layout = {Module.concat([project_module, "Layouts"]), :admin}
    pubsub = Module.concat([project_module, "PubSub"])
    schema = ("Elixir." <> schema_name) |> String.to_atom()
    singular = String.split(schema_name, ".") |> List.last()
    plural = singular <> "s"
    event_prefix = Phoenix.Naming.underscore(singular) <> "_"
    topic = Phoenix.Naming.underscore(plural)
    fields = []

    %LiveResource{
      module: module,
      file: file,
      repo: repo,
      layout: layout,
      schema: schema,
      pubsub: pubsub,
      topic: topic,
      event_prefix: event_prefix,
      singular_name: singular,
      plural_name: plural,
      fields: fields
    }
    |> IO.inspect()
  end
end
