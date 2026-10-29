defmodule Backpex.FormComponentTest do
  use ExUnit.Case, async: true

  alias Backpex.Fields.Upload
  alias Backpex.FormComponent
  alias Backpex.FormComponentTest.PubSub
  alias Phoenix.LiveView.Socket

  # A LiveResource whose adapter reports the params of a changeset to the test instead of building one from a schema,
  # and saves an item without a database.
  defmodule ChangeLive do
    def config(:adapter), do: __MODULE__
    def config(:save_and_continue_button?), do: false
    def translate({msg, _opts}), do: msg
    def can?(_assigns, _action, _item), do: true
    def singular_name, do: "Item"
    def pubsub, do: [server: PubSub, topic: "items"]
    def form_actions(_assigns, default_actions), do: default_actions
    def on_item_creating(socket, change), do: run_hook(socket, :on_item_creating, change)
    def on_item_updating(socket, change), do: run_hook(socket, :on_item_updating, change)
    def on_item_created(_socket, item), do: send(self(), {:on_item_created, item})
    def on_item_updated(_socket, item), do: send(self(), {:on_item_updated, item})
    def return_to(_socket, _assigns, _live_action, _form_action, _item), do: "/items"

    def change(_item, attrs, _fields, _assigns, _live_resource, _opts) do
      send(self(), {:change, attrs})
      Ecto.Changeset.change({%{}, %{title: :string, images: {:array, :string}, docs: {:array, :string}}})
    end

    def insert(changeset, _live_resource), do: Ecto.Changeset.apply_action(changeset, :insert)
    def update(changeset, _live_resource), do: Ecto.Changeset.apply_action(changeset, :update)

    # Calls the function in the `:hook` assign of the form, if any, with the change.
    defp run_hook(socket, name, change) do
      send(self(), {name, change})
      Map.get(socket.assigns, :hook, &Function.identity/1).(change)
    end
  end

  describe "update/2" do
    test "gives a readonly function of an upload field the form on the first update" do
      changeset = Ecto.Changeset.change({%{docs: ["locked.pdf"]}, %{docs: {:array, :string}}})

      field_options = %{
        module: Upload,
        accept: :any,
        max_entries: 1,
        list_existing_files: fn _item -> [] end,
        readonly: fn assigns -> assigns.form[:docs].value == ["locked.pdf"] end
      }

      assigns = %{
        fields: [docs: field_options],
        item: %{},
        changeset: changeset,
        live_resource: ChangeLive,
        live_action: :edit
      }

      assert {:ok, socket} = FormComponent.update(assigns, %Socket{})
      refute Map.has_key?(socket.assigns, :uploads)
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
        module: Upload,
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

    test "ignores the uploads of a field that turned readonly on save" do
      start_supervised!({Phoenix.PubSub, name: PubSub})

      upload_options = fn name ->
        %{
          module: Upload,
          accept: :any,
          max_entries: 1,
          list_existing_files: fn _item -> [] end,
          put_upload_change: fn _socket, params, _item, _uploaded_entries, _removed_entries, _action ->
            Map.put(params, Atom.to_string(name), ["new"])
          end,
          remove_uploads: fn _socket, _item, removed_entries -> send(self(), {:removed, name, removed_entries}) end
        }
      end

      images_options = :images |> upload_options.() |> Map.put(:readonly, true)
      fields = [images: images_options, docs: upload_options.(:docs)]

      # The readonly field got its upload config while it was editable. Its entry isn't done, so consuming it raises.
      socket =
        %Socket{}
        |> Phoenix.Component.assign(fields: fields, item: %{}, live_resource: ChangeLive, live_action: :edit)
        |> Phoenix.Component.assign(removed_uploads: [images: ["old.png"], docs: ["old.pdf"]])
        |> Phoenix.LiveView.allow_upload(:images, accept: :any, max_entries: 1)
        |> Phoenix.LiveView.allow_upload(:docs, accept: :any, max_entries: 1)
        |> put_entry(:images, "0")

      assert {:noreply, socket} = FormComponent.handle_event("save", %{}, socket)
      assert {:live, :redirect, %{to: "/items"}} = socket.redirected

      assert_received {:change, attrs}
      assert attrs["docs"] == ["new"]
      refute Map.has_key?(attrs, "images")

      assert_received {:removed, :docs, ["old.pdf"]}
      refute_received {:removed, :images, _removed_entries}
    end
  end

  describe "handle_event/3 with \"save\"" do
    setup do
      start_supervised!({Phoenix.PubSub, name: PubSub})
      :ok
    end

    test "creates the item from the change on_item_creating/2 returns" do
      hook = &Ecto.Changeset.put_change(&1, :title, "From hook")
      socket = save_socket(:new, hook: hook)

      assert {:noreply, socket} = FormComponent.handle_event("save", %{}, socket)
      assert {:live, :redirect, %{to: "/items"}} = socket.redirected

      assert_received {:on_item_creating, %Ecto.Changeset{}}
      assert_received {:on_item_created, %{title: "From hook"}}
      refute_received {:on_item_updating, _change}
    end

    test "shows the error on_item_creating/2 adds and creates nothing" do
      hook = &Ecto.Changeset.add_error(&1, :title, "is taken")
      socket = save_socket(:new, hook: hook)

      assert {:noreply, socket} = FormComponent.handle_event("save", %{}, socket)
      refute socket.redirected

      assert socket.assigns.show_form_errors
      assert socket.assigns.form.errors == [title: {"is taken", []}]
      refute_received {:on_item_created, _item}
    end

    test "updates the item from the change on_item_updating/2 returns" do
      hook = &Ecto.Changeset.put_change(&1, :title, "From hook")
      socket = save_socket(:edit, hook: hook)

      assert {:noreply, socket} = FormComponent.handle_event("save", %{}, socket)
      assert {:live, :redirect, %{to: "/items"}} = socket.redirected

      assert_received {:on_item_updating, %Ecto.Changeset{}}
      assert_received {:on_item_updated, %{title: "From hook"}}
      refute_received {:on_item_creating, _change}
    end

    test "shows the error on_item_updating/2 adds and saves nothing" do
      hook = &Ecto.Changeset.add_error(&1, :title, "is taken")
      socket = save_socket(:edit, hook: hook)

      assert {:noreply, socket} = FormComponent.handle_event("save", %{}, socket)
      refute socket.redirected

      assert socket.assigns.show_form_errors
      assert socket.assigns.form.errors == [title: {"is taken", []}]
      assert_received {:update_changeset, %Ecto.Changeset{valid?: false}}
      refute_received {:on_item_updated, _item}
    end

    test "raises when on_item_updating/2 does not return the change" do
      socket = save_socket(:edit, hook: fn _change -> %Socket{} end)

      assert_raise ArgumentError, ~r/must return the change they receive/, fn ->
        FormComponent.handle_event("save", %{}, socket)
      end

      refute_received {:on_item_updated, _item}
    end

    defp save_socket(live_action, assigns) do
      %Socket{}
      |> Phoenix.Component.assign(fields: [], item: %{}, live_resource: ChangeLive, live_action: live_action)
      |> Phoenix.Component.assign(removed_uploads: [])
      |> Phoenix.Component.assign(assigns)
    end
  end

  describe "handle_event/3 with \"cancel-entry\"" do
    setup do
      fields = [
        title: %{module: Backpex.Fields.Text, label: "Title"},
        avatar: %{module: Upload, label: "Avatar", upload_key: :avatar}
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
      fields = [photo: %{module: Upload, label: "Photo", upload_key: :avatar}]
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
