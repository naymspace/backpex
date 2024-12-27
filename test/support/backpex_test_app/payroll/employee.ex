defmodule BackpexTestApp.Payroll.Employee do
  use Ecto.Schema
  import Ecto.Changeset

  alias BackpexTestApp.Payroll.{Department, Function}

  schema "employees" do
    field :full_name, :string
    field :address, :string
    field :employee_number, :string
    field :fiscal_number, :integer
    field :begin_date, :date
    field :end_date, :date
    belongs_to :department, Department
    belongs_to :function, Function

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(employee, attrs) do
    employee
    |> cast(attrs, [:full_name, :address, :fiscal_number, :employee_number, :begin_date, :end_date])
    |> cast_assoc(:department)
    |> cast_assoc(:function)
    |> validate_required([:full_name, :address, :fiscal_number, :employee_number, :begin_date, :end_date])
  end

  def update_changeset(employee, attrs, _opts) do
    changeset(employee, attrs)
  end

  def create_changeset(employee, attrs, _opts) do
    changeset(employee, attrs)
  end
end
