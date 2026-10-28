defmodule Backpex.Integration.Authorization.ResourceActionsTest do
  use Backpex.ConnCase, async: true

  alias Phoenix.LiveView.Socket

  test "an authorized submit runs the action", %{conn: conn} do
    insert(:user)

    conn
    |> visit(~p"/admin/users/invite/resource-action")
    |> check("Alex")
    |> fill_in("Text", with: "Please join us")
    |> within("#resource-form", &click_button(&1, "Send email"))
    |> assert_has("div", text: "An email has been successfully sent")
  end

  test "the submit gate raises when the action is denied while the form is open" do
    # The route already refuses an action the user may not open, so the only way to reach the submit gate with a denial
    # is a permission that changed while the modal was open. Drive the form component directly rather than pretend a
    # fixture resource can do that.
    socket =
      assign_socket(
        live_action: :resource_action,
        action_type: :resource,
        live_resource: Backpex.Test.InvoiceLive,
        resource_action: %{module: Backpex.Test.ResourceActions.Email},
        resource_action_id: :invite,
        fields: [],
        item: %{},
        return_to: "/admin/invoices"
      )

    assert_raise Backpex.ForbiddenError, fn ->
      Backpex.FormComponent.handle_event("save", %{"change" => %{}, "save-type" => "save"}, socket)
    end
  end

  defp assign_socket(assigns) do
    Enum.reduce(assigns, %Socket{}, fn {key, value}, socket ->
      Phoenix.Component.assign(socket, key, value)
    end)
  end
end
