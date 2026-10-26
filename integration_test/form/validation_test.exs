defmodule Backpex.Integration.Form.ValidationTest do
  use Backpex.ConnCase, async: true

  test "shows an error for a required field that is empty on submit", %{conn: conn} do
    conn
    |> visit(~p"/admin/tags/new")
    |> fill_in("Name", with: "")
    |> click_button("Save")
    |> assert_path(~p"/admin/tags/new")
    |> assert_has("form#resource-form")
    |> assert_has("p", text: "can't be blank")
  end

  test "shows an error for every invalid field", %{conn: conn} do
    # The country select has no prompt, so it always submits a valid option.
    conn
    |> visit(~p"/admin/addresses/new")
    |> fill_in("Street Name", with: "")
    |> fill_in("Zip Code", with: "")
    |> fill_in("City", with: "")
    |> click_button("Save")
    |> assert_has("form#resource-form")
    |> assert_has("p", text: "can't be blank", count: 3)
  end

  test "clears the error when the field becomes valid", %{conn: conn} do
    conn
    |> visit(~p"/admin/tags/new")
    |> fill_in("Name", with: "")
    |> assert_has("p", text: "can't be blank")
    |> fill_in("Name", with: "Valid Tag Name")
    |> refute_has("p", text: "can't be blank")
  end
end
