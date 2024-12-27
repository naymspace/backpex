defmodule BackpexTestAppWeb.FunctionLive do
  use Backpex.LiveResource,
    adapter_config: [
      schema: BackpexTestApp.Payroll.Function,
      repo: BackpexTestApp.Repo,
      update_changeset: &BackpexTestApp.Payroll.Function.update_changeset/3,
      create_changeset: &BackpexTestApp.Payroll.Function.create_changeset/3
    ],
    layout: {BackpexTestAppWeb.Layouts, :admin},
    pubsub: [
      name: BackpexTestApp.PubSub,
      topic: "functions",
      event_prefix: "function_"
    ]

    @impl Backpex.LiveResource
    def singular_name, do: "Function"

    @impl Backpex.LiveResource
    def plural_name, do: "Functions"

    @impl Backpex.LiveResource
    def fields do
      [
        full_name: %{
          module: Backpex.Fields.Text,
          label: "Name"
        }
      ]
    end
end
