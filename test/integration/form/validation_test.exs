defmodule Backpex.Integration.Form.ValidationTest do
  use Backpex.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "shows an error for a required field that is empty on submit", %{conn: conn} do
    conn
    |> visit(~p"/admin/tags/new")
    |> unwrap(fn view ->
      view
      |> form("#resource-form", change: %{name: ""})
      |> put_submitter("button[value=save]")
      |> render_submit()
    end)
    |> assert_path(~p"/admin/tags/new")
    |> assert_has("form#resource-form")
    |> assert_has("p", text: "can't be blank")
  end

  test "shows an error for every invalid field", %{conn: conn} do
    # The country select has no prompt, so it always submits a valid option.
    conn
    |> visit(~p"/admin/addresses/new")
    |> unwrap(fn view ->
      view
      |> form("#resource-form", change: %{street: "", zip: "", city: ""})
      |> put_submitter("button[value=save]")
      |> render_submit()
    end)
    |> assert_has("form#resource-form")
    |> assert_has("p", text: "can't be blank", count: 3)
  end

  test "clears the error when the field becomes valid", %{conn: conn} do
    conn
    |> visit(~p"/admin/tags/new")
    |> unwrap(fn view ->
      view
      |> form("#resource-form", change: %{name: ""})
      |> render_change()
    end)
    |> unwrap(fn view ->
      view
      |> form("#resource-form", change: %{name: "Valid Tag Name"})
      |> render_change()
    end)
    |> refute_has("p", text: "can't be blank")
  end
end
