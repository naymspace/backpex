defmodule Backpex.FormComponentTest do
  use ExUnit.Case, async: true

  alias Backpex.FormComponent
  alias Phoenix.LiveView.Socket

  # A LiveResource whose adapter reports the params of a changeset to the test instead of building one from a schema.
  defmodule ChangeLive do
    def config(:adapter), do: __MODULE__
    def translate({msg, _opts}), do: msg

    def change(_item, attrs, _fields, _assigns, _live_resource, _opts) do
      send(self(), {:change, attrs})
      Ecto.Changeset.change({%{}, %{images: {:array, :string}, docs: {:array, :string}}})
    end
  end

  describe "handle_event/3" do
    test "ignores events it does not handle" do
      fields = [title: %{module: Backpex.Fields.Text, label: "Title"}]
      socket = Phoenix.Component.assign(%Socket{}, :fields, fields)

      assert FormComponent.handle_event("unknown", %{}, socket) == {:noreply, socket}
      assert FormComponent.handle_event("cancel-entry", %{}, socket) == {:noreply, socket}
    end

    test "drops the changes of readonly fields on a save without params" do
      upload_options = %{
        module: Backpex.Fields.Upload,
        accept: :any,
        max_entries: 1,
        list_existing_files: fn _item -> [] end,
        put_upload_change: fn _socket, params, _item, _uploaded_entries, _removed_entries, _action ->
          Map.merge(params, %{"images" => ["new.png"], "docs" => ["new.pdf"]})
        end
      }

      fields = [images: Map.put(upload_options, :readonly, true), docs: upload_options]

      # The editable field has a refused file, so the save stops before it reaches the database.
      socket =
        %Socket{}
        |> Phoenix.Component.assign(fields: fields, item: %{}, live_resource: ChangeLive, live_action: :edit)
        |> Phoenix.Component.assign(removed_uploads: [])
        |> Phoenix.LiveView.allow_upload(:docs, accept: :any, max_entries: 1)

      socket = Phoenix.Component.update(socket, :uploads, &put_in(&1.docs.errors, [{&1.docs.ref, :too_many_files}]))

      FormComponent.handle_event("save", %{}, socket)

      assert_received {:change, attrs}
      assert attrs["docs"] == ["new.pdf"]
      refute Map.has_key?(attrs, "images")
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
