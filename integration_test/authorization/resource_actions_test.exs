defmodule Backpex.Integration.Authorization.ResourceActionsTest do
  use Backpex.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Phoenix.LiveView.Socket

  test "an authorized submit runs the action", %{conn: conn} do
    insert(:user)

    {:ok, view, _html} = live(conn, ~p"/admin/users/invite/resource-action")

    result =
      view
      |> form("#resource-form", change: %{text: "Please join us"})
      |> render_submit(%{"change" => %{"users" => ["user_id_alex"]}, "save-type" => "save"})

    assert {:ok, _view, html} = follow_redirect(result, conn)
    assert html =~ "An email has been successfully sent"
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
