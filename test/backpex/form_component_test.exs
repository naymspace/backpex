defmodule Backpex.FormComponentTest do
  use ExUnit.Case, async: true

  alias Backpex.FormComponent
  alias Phoenix.LiveView.Socket

  describe "handle_event/3" do
    test "ignores events it does not handle" do
      fields = [title: %{module: Backpex.Fields.Text, label: "Title"}]
      socket = Phoenix.Component.assign(%Socket{}, :fields, fields)

      assert FormComponent.handle_event("unknown", %{}, socket) == {:noreply, socket}
      assert FormComponent.handle_event("cancel-entry", %{}, socket) == {:noreply, socket}
    end
  end
end
