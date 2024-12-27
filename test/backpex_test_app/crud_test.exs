defmodule Backpex.BackpexTextApp.CrudTests do
  use BackpexTestAppWeb.ConnCase
  import PhoenixTest

  test "/payroll/employees (empty database)", %{conn: conn} do
    conn
    |> visit("/payroll/employees")
    |> assert_has("h1", text: "Employees")
    |> assert_has("p", text: "No Employees found")
    |> assert_has("button", text: "New Employee")
    |> assert_has("button[disabled]", text: "Delete")
  end

  test "/payroll/departments (empty database)", %{conn: conn} do
    conn
    |> visit("/payroll/departments")
    |> assert_has("h1", text: "Departments")
    |> assert_has("p", text: "No Departments found")
    |> assert_has("button", text: "New Department")
    |> assert_has("button[disabled]", text: "Delete")
  end

  test "/payroll/functions (empty database)", %{conn: conn} do
    conn
    |> visit("/payroll/functions")
    |> assert_has("h1", text: "Functions")
    |> assert_has("p", text: "No Functions found")
    |> assert_has("button", text: "New Function")
    |> assert_has("button[disabled]", text: "Delete")
  end
end
