defmodule BackpexTestApp.Repo.Migrations.CreateEmployees do
  use Ecto.Migration

  def change do
    create table(:employees) do
      add :full_name, :string
      add :address, :string
      add :fiscal_number, :integer
      add :employee_number, :string
      add :begin_date, :date
      add :end_date, :date
      add :department_id, references(:departments, on_delete: :nothing)
      add :function_id, references(:functions, on_delete: :nothing)

      timestamps(type: :utc_datetime)
    end

    create index(:employees, [:department_id])
    create index(:employees, [:function_id])
  end
end
