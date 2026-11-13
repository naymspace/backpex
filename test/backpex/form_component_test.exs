defmodule Backpex.FormComponentTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Backpex.Fields.Upload
  alias Backpex.FormComponent
  alias Backpex.FormComponentTest.PubSub
  alias Phoenix.LiveView.Socket
  alias Phoenix.LiveView.UploadEntry

  # Saves with a schemaless changeset and refuses the title "taken", like a unique constraint would.
  defmodule UploadAdapter do
    @types %{title: :string, images: {:array, :string}}

    def change(item, attrs, _fields, _assigns, _live_resource, opts) do
      {item, @types}
      |> Ecto.Changeset.cast(attrs, Map.keys(@types))
      |> Ecto.Changeset.validate_required([:title])
      |> Map.put(:action, Keyword.get(opts, :action, :validate))
    end

    def insert(changeset, _live_resource) do
      send(self(), :saved)

      case Ecto.Changeset.get_field(changeset, :title) do
        "taken" -> {:error, Ecto.Changeset.add_error(changeset, :title, "has already been taken")}
        _title -> Ecto.Changeset.apply_action(changeset, :insert)
      end
    end
  end

  defmodule UploadLive do
    def config(:adapter), do: UploadAdapter
    def can?(assigns, _action, _item), do: Map.get(assigns, :allowed?, true)
    def translate({msg, _opts}), do: msg
    def on_item_creating(_socket, change), do: change
  end

  # A custom upload field. The name of the file decides what `consume_upload/5` returns, and the calls are reported to
  # the test process.
  defmodule StoringUpload do
    # Like `Backpex.Fields.Upload`, the form submits no param of the field: `put_upload_change/7` builds it.
    def param_keys(_field, _assigns), do: []
    def list_existing_files(_field, _item), do: []

    def put_upload_change(_field, _socket, params, _item, {done, _in_progress}, _removed_entries, _action),
      do: Map.put(params, "images", Enum.map(done, & &1.client_name))

    def consume_upload(_field, _socket, _item, _meta, entry) do
      send(self(), {:consume, entry.client_name})

      case entry.client_name do
        "error" <> _rest -> {:error, :disk_full}
        "postpone" <> _rest -> {:postpone, :later}
        "raise" <> _rest -> raise "disk full"
        "bare" <> _rest -> entry.client_name
        name -> {:ok, name}
      end
    end

    def remove_uploads(_field, _socket, _item, removed_entries), do: send(self(), {:remove, removed_entries})
    def discard_uploads(_field, _socket, _item, stored), do: send(self(), {:discard, stored})
  end

  # Answers LiveView's calls to an upload channel, so entries can be consumed without a browser.
  defmodule FakeUploadChannel do
    use GenServer

    def start_link(path), do: GenServer.start_link(__MODULE__, path)

    @impl GenServer
    def init(path), do: {:ok, path}

    @impl GenServer
    def handle_call(:consume_start, _from, path), do: {:reply, {:ok, %{path: path}}, path}
    def handle_call(:consume_done, _from, path), do: {:stop, :normal, :ok, path}
  end

  defmodule Membership do
    use Ecto.Schema

    schema "memberships" do
      field :role, :string
      belongs_to :user, Backpex.FormComponentTest.User
      belongs_to :team, Backpex.FormComponentTest.Team
    end
  end

  defmodule Team do
    use Ecto.Schema

    schema "teams" do
      field :name, :string
    end
  end

  defmodule User do
    use Ecto.Schema

    schema "users" do
      has_many :memberships, Membership
      has_many :teams, through: [:memberships, :team]
      has_many :former_memberships, Membership
      has_many :former_teams, through: [:former_memberships, :team]
    end
  end

  # An action with a form that reports the params of its changeset to the test.
  defmodule RenameAction do
    def fields, do: [title: %{module: Backpex.Fields.Text, label: "Title"}]

    def changeset(item, params, _metadata) do
      send(self(), {:action_change, params})
      Ecto.Changeset.cast(item, params, [:title, :role])
    end

    def handle(socket, data) do
      send(self(), {:handled, data})
      {:ok, socket}
    end

    def handle(socket, _items, data), do: handle(socket, data)
  end

  # A LiveResource whose adapter reports the params of a changeset to the test instead of building one from a schema,
  # and saves an item without a database.
  defmodule ChangeLive do
    def config(:adapter), do: __MODULE__
    def config(:save_and_continue_button?), do: false
    def config(:primary_key), do: :id
    def adapter_config(:schema), do: User
    def fields, do: []
    def get(id, _fields, _assigns, _live_resource), do: {:ok, %{id: id}}
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

    def change(_item, attrs, _fields, _assigns, _live_resource, opts) do
      send(self(), {:change, attrs})
      send(self(), {:assocs, Keyword.get(opts, :assocs)})
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

    test "applies only the assocs of the fields the admin may edit" do
      fields = [
        tags: %{module: Backpex.Fields.Text, label: "Tags", readonly: true},
        notes: %{module: Backpex.Fields.Text, label: "Notes"}
      ]

      # The assocs come from the events of fields, which a crafted client can send for a readonly field too.
      socket =
        Phoenix.Component.assign(%Socket{}, %{
          fields: fields,
          item: %{},
          live_resource: ChangeLive,
          live_action: :edit,
          removed_uploads: [],
          assocs: [tags: [%{id: 1}], notes: [%{id: 2}], unknown: [%{id: 3}]]
        })

      FormComponent.handle_event("validate", %{"change" => %{}, "_target" => ["change", "notes"]}, socket)

      assert_received {:assocs, [notes: [%{id: 2}]]}
    end

    # The assoc of a `Backpex.Fields.HasManyThrough` field has the key of the pivot association, not of the field.
    test "applies only the assocs of the HasManyThrough fields the admin may edit" do
      fields = [
        teams: %{module: Backpex.Fields.HasManyThrough, label: "Teams"},
        former_teams: %{module: Backpex.Fields.HasManyThrough, label: "Former teams", readonly: true}
      ]

      socket =
        Phoenix.Component.assign(%Socket{}, %{
          fields: fields,
          item: %{},
          live_resource: ChangeLive,
          live_action: :edit,
          removed_uploads: [],
          assocs: [memberships: [%{}], former_memberships: [%{}], teams: [%{}]]
        })

      FormComponent.handle_event("validate", %{"change" => %{}, "_target" => ["change", "memberships"]}, socket)

      assert_received {:assocs, [memberships: [%{}]]}
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

  # The changesets of the actions cast `role`, which the form of the action has no field for.
  describe "handle_event/3 of an action" do
    @forged %{"title" => "New", "role" => "admin"}

    test "validates an item action with the params of its fields only" do
      socket = action_socket(action_type: :item, action_to_confirm: %{key: :rename, module: RenameAction})

      FormComponent.handle_event("validate", %{"change" => @forged, "_target" => ["change", "title"]}, socket)

      assert_received {:action_change, %{"title" => "New"} = change}
      refute Map.has_key?(change, "role")
    end

    test "runs an item action with the params of its fields only" do
      socket =
        action_socket(
          action_type: :item,
          action_to_confirm: %{key: :rename, module: RenameAction},
          selected_items: [%{id: 1}]
        )

      assert {:noreply, _socket} = FormComponent.handle_event("save", %{"change" => @forged}, socket)

      assert_received {:handled, %{title: "New"} = data}
      refute Map.has_key?(data, :role)
    end

    test "runs a resource action with the params of its fields only" do
      socket =
        action_socket(
          live_action: :resource_action,
          resource_action: %{module: RenameAction},
          resource_action_id: :rename,
          item: %{}
        )

      params = %{"change" => @forged, "save-type" => "save"}

      assert {:noreply, _socket} = FormComponent.handle_event("save", params, socket)

      assert_received {:change, change}
      assert change == %{"title" => "New"}
    end

    defp action_socket(assigns) do
      %Socket{}
      |> Phoenix.Component.assign(
        fields: RenameAction.fields(),
        action_item: {%{}, %{title: :string, role: :string}},
        live_resource: ChangeLive,
        live_action: :index,
        return_to: "/items",
        removed_uploads: []
      )
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

  describe "saving with uploads" do
    test "doesn't store anything while the changeset is invalid" do
      {:noreply, socket} = ["one.png"] |> upload_socket() |> save("")

      assert {"can't be blank", _opts} = socket.assigns.form.errors[:title]
      refute_received {:consume, _name}
      refute_received :saved
    end

    test "authorizes the save before storing anything" do
      socket = upload_socket(["one.png"], allowed?: false)

      assert_raise Backpex.ForbiddenError, fn -> save(socket) end
      refute_received {:consume, _name}
    end

    test "refuses the save at {:error, reason} and discards the files stored before it" do
      socket = upload_socket(["one.png", "error.png", "three.png"])

      {{:noreply, socket}, log} = with_log(fn -> save(socket) end)

      assert_refused(socket)
      assert log =~ ":disk_full"
      assert_received {:consume, "one.png"}
      assert_received {:consume, "error.png"}
      refute_received {:consume, "three.png"}
      assert_received {:discard, ["one.png"]}
      refute_received :saved
    end

    test "refuses the save at {:postpone, _} and at an exception" do
      for name <- ["postpone.png", "raise.png"] do
        socket = upload_socket([name])

        {{:noreply, socket}, log} = with_log(fn -> save(socket) end)

        assert_refused(socket)
        assert log =~ "could not store a file" or log =~ "did not store a file"
        refute_received {:discard, _stored}
        refute_received :saved
      end
    end

    test "discards the stored files when the save fails" do
      {:noreply, socket} = ["one.png", "two.png"] |> upload_socket() |> save("taken")

      assert {"has already been taken", _opts} = socket.assigns.form.errors[:title]
      assert_received :saved
      assert_received {:discard, ["one.png", "two.png"]}
      refute_received {:remove, _removed}
    end

    test "counts any other value as stored, with a warning" do
      socket = upload_socket(["bare.png"])

      {_result, log} = with_log(fn -> save(socket, "taken") end)

      assert log =~ "expected {:ok, value} or {:error, reason}"
      assert_received {:discard, ["bare.png"]}
    end

    test "doesn't discard direct uploads" do
      socket = upload_socket(["one.png", "error.png"], external: true)

      {{:noreply, socket}, _log} = with_log(fn -> save(socket) end)

      assert_refused(socket)
      assert_received {:consume, "one.png"}
      refute_received {:discard, _stored}
    end
  end

  defp save(socket, title \\ "Title") do
    FormComponent.handle_event("save", %{"change" => %{"title" => title}, "save-type" => "save"}, socket)
  end

  defp assert_refused(socket) do
    assert {"file could not be stored", _opts} = socket.assigns.form.errors[:images]
  end

  # A form for a new item with done entries for the given file names, stored through an upload channel or, with
  # `external: true`, uploaded by the browser.
  defp upload_socket(names, opts \\ []) do
    external = if opts[:external], do: [external: fn _entry, socket -> {:ok, %{}, socket} end], else: []
    socket = Phoenix.LiveView.allow_upload(%Socket{}, :images, [accept: :any, max_entries: 5] ++ external)
    conf = socket.assigns.uploads.images
    entries = for {name, index} <- Enum.with_index(names), do: done_entry(conf, name, index)

    conf =
      if opts[:external] do
        %{conf | entries: entries, entry_refs_to_metas: Map.new(entries, &{&1.ref, %{key: &1.client_name}})}
      else
        %{conf | entries: entries, entry_refs_to_pids: Map.new(entries, &{&1.ref, start_channel()})}
      end

    socket = put_in(socket.assigns.uploads.images, conf)

    Phoenix.Component.assign(socket,
      live_resource: UploadLive,
      live_action: :new,
      fields: [
        images: %{module: StoringUpload, label: "Images"},
        title: %{module: Backpex.Fields.Text, label: "Title"}
      ],
      item: %{},
      removed_uploads: [],
      allowed?: Keyword.get(opts, :allowed?, true)
    )
  end

  defp done_entry(conf, name, index) do
    %UploadEntry{
      ref: "#{index}",
      upload_ref: conf.ref,
      upload_config: :images,
      client_name: name,
      done?: true,
      progress: 100,
      valid?: true,
      preflighted?: true
    }
  end

  defp start_channel do
    {:ok, pid} = start_supervised({FakeUploadChannel, "/tmp/upload"}, id: make_ref())
    pid
  end
end
