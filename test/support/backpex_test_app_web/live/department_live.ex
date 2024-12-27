defmodule BackpexTestAppWeb.DepartmentLive do
  use Backpex.LiveResource,
    adapter_config: [
      schema: BackpexTestApp.Payroll.Department,
      repo: BackpexTestApp.Repo,
      update_changeset: &BackpexTestApp.Payroll.Department.update_changeset/3,
      create_changeset: &BackpexTestApp.Payroll.Department.create_changeset/3
    ],
    layout: {BackpexTestAppWeb.Layouts, :admin},
    pubsub: [
      name: BackpexTestApp.PubSub,
      topic: "departments",
      event_prefix: "department_"
    ]

    @impl Backpex.LiveResource
    def singular_name, do: "Department"

    @impl Backpex.LiveResource
    def plural_name, do: "Departments"

    @impl Backpex.LiveResource
    def fields do
      [
        name: %{
          module: Backpex.Fields.Text,
          label: "Name"
        }
      ]
    end
end
