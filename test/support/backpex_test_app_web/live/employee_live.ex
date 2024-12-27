defmodule BackpexTestAppWeb.EmployeeLive do
  use Backpex.LiveResource,
    adapter_config: [
      schema: BackpexTestApp.Payroll.Employee,
      repo: BackpexTestApp.Repo,
      update_changeset: &BackpexTestApp.Payroll.Employee.update_changeset/3,
      create_changeset: &BackpexTestApp.Payroll.Employee.create_changeset/3
    ],
    layout: {BackpexTestAppWeb.Layouts, :admin},
    pubsub: [
      name: BackpexTestApp.PubSub,
      topic: "employees",
      event_prefix: "employee_"
    ]

    @impl Backpex.LiveResource
    def singular_name, do: "Employee"

    @impl Backpex.LiveResource
    def plural_name, do: "Employees"

    @impl Backpex.LiveResource
    def fields do
      [
        full_name: %{
          module: Backpex.Fields.Text,
          label: "Full name"
        },
        address: %{
          module: Backpex.Fields.Text,
          label: "Address"
        },
        employee_number: %{
          module: Backpex.Fields.Text,
          label: "Employee number"
        },
        fiscal_number: %{
          module: Backpex.Fields.Number,
          label: "Fiscal number"
        },
        begin_date: %{
          module: Backpex.Fields.Date,
          label: "Begin date"
        },
        end_date: %{
          module: Backpex.Fields.Date,
          label: "End date"
        },
        department: %{
          module: Backpex.Fields.BelongsTo,
          display_field: :name,
          label: "Department",
          prompt: ""
        },
        function: %{
          module: Backpex.Fields.BelongsTo,
          display_field: :name,
          label: "Function",
          prompt: ""
        }
      ]
    end
end
