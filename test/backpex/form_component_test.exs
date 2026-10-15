defmodule Backpex.FormComponentTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Backpex.FormComponent
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
  end

  # A custom upload field. The name of the file decides what `consume_upload/5` returns, and the calls are reported to
  # the test process.
  defmodule StoringUpload do
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

  describe "handle_event/3" do
    test "ignores events it does not handle" do
      fields = [title: %{module: Backpex.Fields.Text, label: "Title"}]
      socket = Phoenix.Component.assign(%Socket{}, :fields, fields)

      assert FormComponent.handle_event("unknown", %{}, socket) == {:noreply, socket}
      assert FormComponent.handle_event("cancel-entry", %{}, socket) == {:noreply, socket}
    end
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
