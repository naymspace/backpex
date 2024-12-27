# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     BackpexTestApp.Repo.insert!(%BackpexTestApp.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias BackpexTestApp.Repo
alias BackpexTestApp.Payroll.Employee
alias BackpexTestApp.Payroll.Department
alias BackpexTestApp.Payroll.Function


departments =
  for name <- ["Marketing", "Sales", "Accounting"] do
    Repo.insert!(%Department{name: name})
  end

functions =
  for name <- ["Secretary", "Programmer", "Manager"] do
    Repo.insert!(%Function{name: name})
  end

# Deterministic date for "today"
today = ~D[2024-11-11]
oldest_date = ~D[1974-04-15]

_employees =
  for i <- 1..100 do
    department = Enum.random(departments)
    function = Enum.random(functions)

    end_date = Faker.Date.between(oldest_date, today)
    begin_date = Faker.Date.between(oldest_date, end_date)

    full_name = "#{Faker.Name.first_name()} #{Faker.Name.last_name()}"

    employee =
      %Employee{
        full_name: full_name,
        address: Faker.Address.street_address(),
        # The following implementation (string instead of integer)
        # is actually the correct way of impolementing an identifier.
        employee_number: "EN#{Enum.random(10_000..99_999)}",
        # This "bad" implementation using an integer is on purpose;
        # This could be due to bad legacy code.
        fiscal_number: Enum.random(10_000..99_999),
        end_date: end_date,
        begin_date: begin_date,
        function_id: department.id,
        department_id: function.id
      }

    Repo.insert!(employee)
  end
