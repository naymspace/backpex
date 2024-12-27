defmodule Backpex.BackpexTextApp.CrudTests do
  use BackpexTestAppWeb.ConnCase
  import PhoenixTest
  require Ecto.Query, as: Query

  alias BackpexTestApp.Repo
  alias BackpexTestApp.Payroll.{
    Function,
    Department,
    Employee
  }

  def populate_database(opts \\ []) do
    seed = Keyword.get(opts, :seed, 42)
    n_employees = Keyword.get(opts, :n_employees, 100)

    :rand.seed(:exsss, {seed, seed + 1, seed + 2})

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

    employees =
      for _i <- 1..n_employees do
        department = Enum.random(departments)
        function = Enum.random(functions)

        end_date = Faker.Date.between(oldest_date, today)
        begin_date = Faker.Date.between(oldest_date, end_date)

        full_name = "#{Faker.Person.first_name()} #{Faker.Person.last_name()}"

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

    %{
      departments: departments,
      functions: functions,
      employees: employees
    }
  end

  def reset_database() do
    Repo.delete_all(Employee)
    Repo.delete_all(Department)
    Repo.delete_all(Function)

    :ok
  end

  def with_populated_database(opts \\ [], fun) do
    try do
      data = populate_database(opts)
      fun.(data)
    after
      reset_database()
    end
  end

  describe "index page for empty database:" do
    test "/payroll/employees", %{conn: conn} do
      conn
      |> visit("/payroll/employees")
      |> assert_has("h1", text: "Employees")
      |> assert_has("p", text: "No Employees found")
      |> assert_has("button", text: "New Employee")
      |> assert_has("button[disabled]", text: "Delete")
    end

    test "/payroll/departments", %{conn: conn} do
      conn
      |> visit("/payroll/departments")
      |> assert_has("h1", text: "Departments")
      |> assert_has("p", text: "No Departments found")
      |> assert_has("button", text: "New Department")
      |> assert_has("button[disabled]", text: "Delete")
    end

    test "/payroll/functions", %{conn: conn} do
      conn
      |> visit("/payroll/functions")
      |> assert_has("h1", text: "Functions")
      |> assert_has("p", text: "No Functions found")
      |> assert_has("button", text: "New Function")
      |> assert_has("button[disabled]", text: "Delete")
    end
  end

  describe "index page for filled database: " do
    test "/payroll/employees", %{conn: conn} do
      with_populated_database(fn _data ->
        conn
        |> visit("/payroll/employees")
        |> assert_has("h1", text: "Employees")
        |> assert_has("button", text: "New Employee")
        |> assert_has("button[disabled]", text: "Delete")
        |> refute_has("p", text: "No Employees found")
      end)
    end

    test "/payroll/departments", %{conn: conn} do
      with_populated_database(fn _data ->
        conn
        |> visit("/payroll/departments")
        |> assert_has("h1", text: "Departments")
        |> assert_has("button", text: "New Department")
        |> assert_has("button[disabled]", text: "Delete")
        |> refute_has("p", text: "No Departments found")
      end)
    end

    test "/payroll/functions", %{conn: conn} do
      with_populated_database(fn _data ->
        conn
        |> visit("/payroll/functions")
        |> assert_has("h1", text: "Functions")
        |> assert_has("button", text: "New Function")
        |> assert_has("button[disabled]", text: "Delete")
        |> refute_has("p", text: "No Functions found")
      end)
    end

    test "database is empty before and after each `with_popyulated_database/1` call" do
      # Nothing has remained inside the database after the previous tests
      assert Repo.all(Employee) == []
      assert Repo.all(Department) == []
      assert Repo.all(Function) == []

      # Populated the database and do nothing to empty it
      with_populated_database(fn _data ->
        :ok
      end)

      # Ensure the database is empty
      assert Repo.all(Employee) == []
      assert Repo.all(Department) == []
      assert Repo.all(Function) == []
    end
  end

  describe "create new resource:" do
    test "/payroll/departments (button below title)", %{conn: conn} do
      conn
      |> visit("/payroll/departments")
      |> click_link("p + a[href='/payroll/departments/new']", "New Department")
      # Title of the page
      |> assert_has("h1", text: "New Department")
      # Full name input
      |> assert_has("label", text: "Name")
      |> assert_has("input[name='change[name]']")
      |> assert_has("input#change_name")
    end

    test "/payroll/departments (button at the middle of the table)", %{conn: conn} do
      conn
      |> visit("/payroll/departments")
      |> click_link("h1 + div > a[href='/payroll/departments/new']", "New Department")
      # Title of the page
      |> assert_has("h1", text: "New Department")
      # Full name input
      |> assert_has("label", text: "Name")
      |> assert_has("input[name='change[name]']")
      |> assert_has("input#change_name")
    end

    test "/payroll/departments (button below title, with filled database)", %{conn: conn} do
      with_populated_database(fn _data ->
        conn
        |> visit("/payroll/departments")
        |> click_link("h1 + div > a[href='/payroll/departments/new']", "New Department")
        # Title of the page
        |> assert_has("h1", text: "New Department")
        # Full name input
        |> assert_has("label", text: "Name")
        |> assert_has("input[name='change[name]']")
        |> assert_has("input#change_name")
      end)
    end

    test "/payroll/functions (button below title)", %{conn: conn} do
      conn
      |> visit("/payroll/functions")
      |> click_link("p + a[href='/payroll/functions/new']", "New Function")
      # Title of the page
      |> assert_has("h1", text: "New Function")
      # Full name input
      |> assert_has("label", text: "Name")
      |> assert_has("input[name='change[name]']")
      |> assert_has("input#change_name")
    end

    test "/payroll/functions (button at the middle of the table)", %{conn: conn} do
      conn
      |> visit("/payroll/functions")
      |> click_link("h1 + div > a[href='/payroll/functions/new']", "New Function")
      # Title of the page
      |> assert_has("h1", text: "New Function")
      # Full name input
      |> assert_has("label", text: "Name")
      |> assert_has("input[name='change[name]']")
      |> assert_has("input#change_name")
    end

    test "/payroll/functions (button below title, with filled database)", %{conn: conn} do
      with_populated_database(fn _data ->
        conn
        |> visit("/payroll/functions")
        |> click_link("h1 + div > a[href='/payroll/functions/new']", "New Function")
        # Title of the page
        |> assert_has("h1", text: "New Function")
        # Full name input
        |> assert_has("label", text: "Name")
        |> assert_has("input[name='change[name]']")
        |> assert_has("input#change_name")
      end)
    end

    test "/payroll/employees (button below title)", %{conn: conn} do
      conn
      |> visit("/payroll/employees")
      |> click_link("p + a[href='/payroll/employees/new']", "New Employee")
      # Title of the page
      |> assert_has("h1", text: "New Employee")
      # Full name input
      |> assert_has("label", text: "Full name")
      |> assert_has("input[name='change[full_name]']")
      |> assert_has("input#change_full_name")
      # Address input
      |> assert_has("label", text: "Address")
      |> assert_has("input[name='change[address]']")
      |> assert_has("input#change_address")
      # Employee number input
      |> assert_has("label", text: "Employee number")
      |> assert_has("input[name='change[employee_number]']")
      |> assert_has("input#change_employee_number")
      # Fiscal number input
      |> assert_has("label", text: "Fiscal number")
      |> assert_has("input[name='change[fiscal_number]']")
      |> assert_has("input#change_fiscal_number")
      # Begin date input
      |> assert_has("label", text: "Begin date")
      |> assert_has("input[name='change[begin_date]']")
      |> assert_has("input#change_begin_date")
      # End date input
      |> assert_has("label", text: "End date")
      |> assert_has("input[name='change[end_date]']")
      |> assert_has("input#change_end_date")
      # Department input
      |> assert_has("label", text: "Department")
      |> assert_has("select[name='change[department_id]']")
      # Function input
      |> assert_has("label", text: "Function")
      |> assert_has("select[name='change[function_id]']")
    end

    test "/payroll/employees (button at the middle of the table)", %{conn: conn} do
      conn
      |> visit("/payroll/employees")
      |> click_link("h1 + div > a[href='/payroll/employees/new']", "New Employee")
      # Title of the page
      |> assert_has("h1", text: "New Employee")
      # Full name input
      |> assert_has("label", text: "Full name")
      |> assert_has("input[name='change[full_name]']")
      |> assert_has("input#change_full_name")
      # Address input
      |> assert_has("label", text: "Address")
      |> assert_has("input[name='change[address]']")
      |> assert_has("input#change_address")
      # Employee number input
      |> assert_has("label", text: "Employee number")
      |> assert_has("input[name='change[employee_number]']")
      |> assert_has("input#change_employee_number")
      # Fiscal number input
      |> assert_has("label", text: "Fiscal number")
      |> assert_has("input[name='change[fiscal_number]']")
      |> assert_has("input#change_fiscal_number")
      # Begin date input
      |> assert_has("label", text: "Begin date")
      |> assert_has("input[name='change[begin_date]']")
      |> assert_has("input#change_begin_date")
      # End date input
      |> assert_has("label", text: "End date")
      |> assert_has("input[name='change[end_date]']")
      |> assert_has("input#change_end_date")
      # Department input
      |> assert_has("label", text: "Department")
      |> assert_has("select[name='change[department_id]']")
      # Function input
      |> assert_has("label", text: "Function")
      |> assert_has("select[name='change[function_id]']")
    end

    test "/payroll/employees (button below title, with filled database)", %{conn: conn} do
      with_populated_database(fn _data ->
        conn
        |> visit("/payroll/employees")
        |> click_link("h1 + div > a[href='/payroll/employees/new']", "New Employee")
        # Title of the page
        |> assert_has("h1", text: "New Employee")
        # Full name input
        |> assert_has("label", text: "Full name")
        |> assert_has("input[name='change[full_name]']")
        |> assert_has("input#change_full_name")
        # Address input
        |> assert_has("label", text: "Address")
        |> assert_has("input[name='change[address]']")
        |> assert_has("input#change_address")
        # Employee number input
        |> assert_has("label", text: "Employee number")
        |> assert_has("input[name='change[employee_number]']")
        |> assert_has("input#change_employee_number")
        # Fiscal number input
        |> assert_has("label", text: "Fiscal number")
        |> assert_has("input[name='change[fiscal_number]']")
        |> assert_has("input#change_fiscal_number")
        # Begin date input
        |> assert_has("label", text: "Begin date")
        |> assert_has("input[name='change[begin_date]']")
        |> assert_has("input#change_begin_date")
        # End date input
        |> assert_has("label", text: "End date")
        |> assert_has("input[name='change[end_date]']")
        |> assert_has("input#change_end_date")
        # Department input
        |> assert_has("label", text: "Department")
        |> assert_has("select[name='change[department_id]']")
        # Function input
        |> assert_has("label", text: "Function")
        |> assert_has("select[name='change[function_id]']")
      end)
    end
  end

  describe "edit resource:" do
    test "/payroll/departments - can save and continue (no change)", %{conn: conn} do
      with_populated_database(fn _data ->
        department = Repo.one(Query.from d in Department, order_by: d.id, limit: 1)

        conn
        |> visit("/payroll/departments/#{department.id}/edit")
        # We are in the editing page
        |> assert_has("h1", text: "Edit Department")
        |> click_button("button", "Save & Continue editing")
        # We're still in the editing page (i.e. we didn't move anywhere else)
        |> assert_has("h1", text: "Edit Department")
      end)
    end

    test "/payroll/departments - can save and continue (with change)", %{conn: conn} do
      with_populated_database(fn _data ->
        department = Repo.one(Query.from d in Department, order_by: d.id, limit: 1)

        conn
        |> visit("/payroll/departments/#{department.id}/edit")
        # We are in the editing page
        |> assert_has("h1", text: "Edit Department")
        |> fill_in("Name", with: "New Department Name")
        |> click_button("button", "Save & Continue editing")
        # We're still in the editing page (i.e. we didn't move anywhere else)
        |> assert_has("h1", text: "Edit Department")

        # Get the updated resource from the database and ensure the name has been changed
        updated_department = Repo.get!(Department, department.id)

        assert updated_department.name == "New Department Name"
      end)
    end

    test "/payroll/functions - can save and continue (no change)", %{conn: conn} do
      with_populated_database(fn _data ->
        function = Repo.one(Query.from f in Function, order_by: f.id, limit: 1)

        conn
        |> visit("/payroll/functions/#{function.id}/edit")
        # We are in the editing page
        |> assert_has("h1", text: "Edit Function")
        |> click_button("button", "Save & Continue editing")
        # We're still in the editing page (i.e. we didn't move anywhere else)
        |> assert_has("h1", text: "Edit Function")
      end)
    end

    test "/payroll/functions - can save and continue (with change)", %{conn: conn} do
      with_populated_database(fn _data ->
        function = Repo.one(Query.from f in Function, order_by: f.id, limit: 1)

        conn
        |> visit("/payroll/functions/#{function.id}/edit")
        # We are in the editing page
        |> assert_has("h1", text: "Edit Function")
        |> fill_in("Name", with: "New Function Name")
        |> click_button("button", "Save & Continue editing")
        # We're still in the editing page (i.e. we didn't move anywhere else)
        |> assert_has("h1", text: "Edit Function")

        # Get the updated resource from the database and ensure the name has been changed
        updated_function = Repo.get!(Function, function.id)

        assert updated_function.name == "New Function Name"
      end)
    end

    test "/payroll/employees - can save and continue (no change)", %{conn: conn} do
      with_populated_database(fn _data ->
        employee = Repo.one(Query.from e in Employee, order_by: e.id, limit: 1)

        conn
        |> visit("/payroll/employees/#{employee.id}/edit")
        # We are in the editing page
        |> assert_has("h1", text: "Edit Employee")
        |> click_button("button", "Save & Continue editing")
        # We're still in the editing page (i.e. we didn't move anywhere else)
        |> assert_has("h1", text: "Edit Employee")
      end)
    end

    test "/payroll/employees - can save and continue (with change)", %{conn: conn} do
      with_populated_database(fn _data ->
        employee = Repo.one(Query.from e in Employee, order_by: e.id, limit: 1)

        conn
        |> visit("/payroll/employees/#{employee.id}/edit")
        # We are in the editing page
        |> assert_has("h1", text: "Edit Employee")
        |> fill_in("Full name", with: "New Employee Name")
        |> click_button("button", "Save & Continue editing")
        # We're still in the editing page (i.e. we didn't move anywhere else)
        |> assert_has("h1", text: "Edit Employee")

        # Get the updated resource from the database and ensure the name has been changed
        updated_employee = Repo.get!(Employee, employee.id)

        assert updated_employee.full_name == "New Employee Name"
      end)
    end

    test "/payroll/employees - clicking 'Save' moves to index (no change)", %{conn: conn} do
      with_populated_database(fn _data ->
        employee = Repo.one(Query.from e in Employee, order_by: e.id, limit: 1)

        conn
        |> visit("/payroll/employees/#{employee.id}/edit")
        # We are in the editing page
        |> assert_has("h1", text: "Edit Employee")
        |> click_button("button[value='save']", "Save")
        # We're note in the editing page anymore
        |> refute_has("h1", text: "Edit Employee")
        # We're in the index page
        |> assert_has("h1", text: "Employees")
      end)
    end

    test "/payroll/employees - clicking 'Save' moves to index (with change)", %{conn: conn} do
      with_populated_database(fn _data ->
        employee = Repo.one(Query.from e in Employee, order_by: e.id, limit: 1)

        conn
        |> visit("/payroll/employees/#{employee.id}/edit")
        # We are in the editing page
        |> assert_has("h1", text: "Edit Employee")
        |> fill_in("Full name", with: "New Employee Name")
        |> click_button("button[value='save']", "Save")
        # We're note in the editing page anymore
        |> refute_has("h1", text: "Edit Employee")
        # We're in the index page
        |> assert_has("h1", text: "Employees")

        # Get the updated resource from the database and ensure the name has been changed
        updated_employee = Repo.get!(Employee, employee.id)

        assert updated_employee.full_name == "New Employee Name"
      end)
    end
  end
end
