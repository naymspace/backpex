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

  describe "handle_event/3 with \"cancel-entry\"" do
    setup do
      fields = [
        title: %{module: Backpex.Fields.Text, label: "Title"},
        avatar: %{module: Backpex.Fields.Upload, label: "Avatar", upload_key: :avatar}
      ]

      socket =
        %Socket{}
        |> Phoenix.Component.assign(:fields, fields)
        |> Phoenix.LiveView.allow_upload(:avatar, accept: :any)
        |> put_entry(:avatar, "0")

      %{socket: socket}
    end

    test "cancels a pending entry", %{socket: socket} do
      assert {:noreply, socket} = FormComponent.handle_event("cancel-entry", %{"ref" => "0", "id" => "avatar"}, socket)
      assert socket.assigns.uploads.avatar.entries == []
      assert socket.private.live_temp.push_events == [["cancel-entry:avatar", %{}]]
    end

    test "ignores a ref without a pending entry", %{socket: socket} do
      assert FormComponent.handle_event("cancel-entry", %{"ref" => "1", "id" => "avatar"}, socket) == {:noreply, socket}
    end

    test "ignores an entry that is already cancelled", %{socket: socket} do
      # An entry with a running upload stays in `entries` as `cancelled?` until its channel shuts down.
      socket =
        Phoenix.Component.update(socket, :uploads, fn uploads ->
          update_in(uploads.avatar.entries, &Enum.map(&1, fn entry -> %{entry | cancelled?: true} end))
        end)

      assert FormComponent.handle_event("cancel-entry", %{"ref" => "0", "id" => "avatar"}, socket) == {:noreply, socket}
    end

    test "ignores a key that is not an upload", %{socket: socket} do
      assert FormComponent.handle_event("cancel-entry", %{"ref" => "0", "id" => "fields"}, socket) == {:noreply, socket}
      assert FormComponent.handle_event("cancel-entry", %{"ref" => "0", "id" => "title"}, socket) == {:noreply, socket}
    end

    test "ignores a key that is not an existing atom", %{socket: socket} do
      params = %{"ref" => "0", "id" => "not_an_existing_atom_#{System.unique_integer([:positive])}"}

      assert FormComponent.handle_event("cancel-entry", params, socket) == {:noreply, socket}
    end

    test "ignores an entry of a readonly field", %{socket: socket} do
      socket = Phoenix.Component.update(socket, :fields, &put_in(&1, [:avatar, :readonly], true))

      assert FormComponent.handle_event("cancel-entry", %{"ref" => "0", "id" => "avatar"}, socket) == {:noreply, socket}
    end

    test "ignores an entry of a field that is readonly by a function", %{socket: socket} do
      socket = Phoenix.Component.update(socket, :fields, &put_in(&1, [:avatar, :readonly], fn _assigns -> true end))

      assert FormComponent.handle_event("cancel-entry", %{"ref" => "0", "id" => "avatar"}, socket) == {:noreply, socket}
    end

    test "ignores params that are not binaries", %{socket: socket} do
      assert FormComponent.handle_event("cancel-entry", %{"ref" => "0", "id" => 1}, socket) == {:noreply, socket}
      assert FormComponent.handle_event("cancel-entry", %{"ref" => 0, "id" => "avatar"}, socket) == {:noreply, socket}
    end

    test "matches the upload key, not the field name", %{socket: socket} do
      fields = [photo: %{module: Backpex.Fields.Upload, label: "Photo", upload_key: :avatar}]
      socket = Phoenix.Component.assign(socket, :fields, fields)

      assert FormComponent.handle_event("cancel-entry", %{"ref" => "0", "id" => "photo"}, socket) == {:noreply, socket}

      assert {:noreply, socket} = FormComponent.handle_event("cancel-entry", %{"ref" => "0", "id" => "avatar"}, socket)
      assert socket.assigns.uploads.avatar.entries == []
      assert socket.private.live_temp.push_events == [["cancel-entry:avatar", %{}]]
    end
  end

  # Registers a client entry the way the LiveView channel does when the user picks a file.
  defp put_entry(socket, name, ref) do
    entry = %{"ref" => ref, "name" => "avatar.png", "type" => "image/png", "size" => 1, "last_modified" => 0}
    {:ok, socket} = Phoenix.LiveView.Upload.put_entries(socket, socket.assigns.uploads[name], [entry], nil)
    socket
  end
end
