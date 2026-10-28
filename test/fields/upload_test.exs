defmodule Backpex.Fields.UploadTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Backpex.Field
  alias Backpex.Fields.Upload
  alias Phoenix.LiveView.Socket
  alias Phoenix.LiveView.UploadConfig
  alias Phoenix.LiveView.UploadEntry

  # An upload field that delegates rendering to `Backpex.Fields.Upload` and gives texts of its own for upload errors.
  defmodule ErrorTextsUpload do
    use Backpex.Field, config_schema: Upload.config_schema()

    @impl Backpex.Field
    def render_value(assigns), do: Upload.render_value(assigns)

    @impl Backpex.Field
    def render_form(assigns), do: Upload.render_form(assigns)

    @impl Backpex.Field
    def upload_error({name, _field_options}, :too_many_files, upload, _assigns),
      do: "at most #{upload.max_entries} #{name}"

    def upload_error(_field, {:external_metadata_failure, %{reason: reason}}, _upload, _assigns),
      do: "refused: #{reason}"

    def upload_error(field, error, upload, assigns), do: Upload.upload_error(field, error, upload, assigns)
  end

  # A LiveResource that returns Backpex's texts untranslated, with their bindings filled in.
  defmodule UntranslatedLive do
    def translate({msg, opts}) do
      Enum.reduce(opts, msg, fn {key, value}, msg -> String.replace(msg, "%{#{key}}", to_string(value)) end)
    end
  end

  # An upload field that works out its files from the field instead of taking a function per field.
  defmodule NamedFilesUpload do
    def list_existing_files({name, _field_options} = _field, item), do: Map.get(item, name, [])
    def put_upload_change(_field, _socket, params, _item, _uploaded_entries, _removed_entries, _action), do: params
    def consume_upload(_field, _socket, _item, _meta, _entry), do: {:ok, "new.png"}
    def remove_uploads(_field, _socket, _item, _removed_entries), do: :ok
  end

  # An upload field from before the callbacks existed: it reuses the config schema of `Backpex.Fields.Upload`, so it
  # takes the four functions as options, and implements no upload callback itself.
  defmodule OptionsUpload do
    use Backpex.Field, config_schema: Upload.config_schema()

    @impl Backpex.Field
    def render_value(assigns), do: Upload.render_value(assigns)

    @impl Backpex.Field
    def render_form(assigns), do: Upload.render_form(assigns)

    @impl Backpex.Field
    def assign_uploads(field, socket), do: Upload.assign_uploads(field, socket)
  end

  describe "upload_module/1" do
    test "is the module of a field that implements the upload callbacks" do
      assert Field.upload_module({:images, %{module: Upload}}) == Upload
      assert Field.upload_module({:images, %{module: NamedFilesUpload}}) == NamedFilesUpload
    end

    test "is Backpex.Fields.Upload for a field that takes the upload functions as options" do
      assert Field.upload_module({:images, %{module: OptionsUpload, upload_key: :images}}) == Upload
    end
  end

  describe "upload_key/1" do
    test "is the name of a field that implements the upload callbacks" do
      assert Field.upload_key({:images, %{module: Upload}}) == :images
      assert Field.upload_key({:images, %{module: NamedFilesUpload}}) == :images
    end

    test "is the upload_key option when given" do
      assert Field.upload_key({:images, %{module: Upload, upload_key: :pictures}}) == :pictures
      assert Field.upload_key({:images, %{module: OptionsUpload, upload_key: :pictures}}) == :pictures
    end

    test "is nil for a field without upload callbacks and upload_key" do
      assert Field.upload_key({:images, %{module: OptionsUpload}}) == nil
      assert Field.upload_key({:title, %{module: Backpex.Fields.Text}}) == nil
    end
  end

  describe "list_existing_files/3" do
    test "calls the list_existing_files option of Backpex.Fields.Upload" do
      field = {:images, %{module: Upload, list_existing_files: fn item -> item.images end}}

      assert Upload.list_existing_files(field, %{images: ["a.png", "b.png"]}, ["a.png"]) == ["b.png"]
    end

    test "calls list_existing_files/2 of a custom upload field" do
      field = {:images, %{module: NamedFilesUpload}}

      assert Upload.list_existing_files(field, %{images: ["a.png", "b.png"]}, ["b.png"]) == ["a.png"]
      assert Upload.existing_file_paths(field, %{images: ["a.png"]}, []) == [{"a.png", "a.png"}]
    end

    test "calls the list_existing_files option of a custom field without callbacks" do
      field = {:images, %{module: OptionsUpload, upload_key: :images, list_existing_files: fn item -> item.images end}}

      assert Upload.list_existing_files(field, %{images: ["a.png", "b.png"]}, ["a.png"]) == ["b.png"]
    end
  end

  describe "upload callbacks" do
    setup do
      test = self()

      field_options = %{
        module: Upload,
        list_existing_files: fn item -> item.images end,
        put_upload_change: fn socket, params, item, uploaded_entries, removed_entries, action ->
          send(test, {:put_upload_change, socket, item, uploaded_entries, removed_entries, action})
          Map.put(params, "images", ["new.png"])
        end,
        consume_upload: fn socket, item, meta, entry ->
          send(test, {:consume_upload, socket, item, meta, entry})
          {:ok, "new.png"}
        end,
        remove_uploads: fn socket, item, removed_entries ->
          send(test, {:remove_uploads, socket, item, removed_entries})
          :ok
        end
      }

      %{field: {:images, field_options}, item: %{images: ["old.png"]}}
    end

    test "are called on Backpex.Fields.Upload for a custom field without callbacks", %{field: field, item: item} do
      {name, field_options} = field
      field = {name, %{field_options | module: OptionsUpload}}
      module = Field.upload_module(field)

      assert module.list_existing_files(field, item) == ["old.png"]
      assert module.put_upload_change(field, :socket, %{}, item, {[], []}, [], :validate) == %{"images" => ["new.png"]}
      assert module.consume_upload(field, :socket, item, %{}, :entry) == {:ok, "new.png"}
      assert module.remove_uploads(field, :socket, item, ["old.png"]) == :ok
      assert_received {:put_upload_change, :socket, ^item, {[], []}, [], :validate}
      assert_received {:consume_upload, :socket, ^item, %{}, :entry}
      assert_received {:remove_uploads, :socket, ^item, ["old.png"]}
    end

    test "list_existing_files/2 calls the option", %{field: field, item: item} do
      assert Upload.list_existing_files(field, item) == ["old.png"]
    end

    test "put_upload_change/7 calls the option", %{field: field, item: item} do
      params = Upload.put_upload_change(field, :socket, %{}, item, {[:entry], []}, ["old.png"], :insert)

      assert params == %{"images" => ["new.png"]}
      assert_received {:put_upload_change, :socket, ^item, {[:entry], []}, ["old.png"], :insert}
    end

    test "consume_upload/5 calls the option", %{field: field, item: item} do
      assert Upload.consume_upload(field, :socket, item, %{path: "/tmp/upload"}, :entry) == {:ok, "new.png"}
      assert_received {:consume_upload, :socket, ^item, %{path: "/tmp/upload"}, :entry}
    end

    test "remove_uploads/4 calls the option", %{field: field, item: item} do
      assert Upload.remove_uploads(field, :socket, item, ["old.png"]) == :ok
      assert_received {:remove_uploads, :socket, ^item, ["old.png"]}
    end
  end

  describe "validate_config!/2" do
    setup do
      options = [
        module: Upload,
        label: "Images",
        list_existing_files: fn item -> item.images end,
        put_upload_change: fn _socket, params, _item, _uploaded_entries, _removed_entries, _action -> params end,
        consume_upload: fn _socket, _item, _meta, _entry -> {:ok, "new.png"} end,
        remove_uploads: fn _socket, _item, _removed_entries -> :ok end
      ]

      %{options: options}
    end

    test "accepts a positive max_entries", %{options: options} do
      validated = Upload.validate_config!({:images, Keyword.put(options, :max_entries, 1)}, UntranslatedLive)

      assert validated[:max_entries] == 1
    end

    test "rejects max_entries: 0", %{options: options} do
      assert_raise RuntimeError, ~r/field "images".*invalid value for :max_entries option/s, fn ->
        Upload.validate_config!({:images, Keyword.put(options, :max_entries, 0)}, UntranslatedLive)
      end
    end
  end

  describe "assign_uploads/2" do
    setup do
      field_options = %{
        module: Upload,
        accept: :any,
        max_entries: 1,
        list_existing_files: fn item -> item.images end
      }

      socket = Phoenix.Component.assign(%Socket{}, :item, %{images: ["old.png"]})

      %{field_options: field_options, socket: socket}
    end

    test "names the upload after the field without an upload_key", %{field_options: field_options, socket: socket} do
      socket = Upload.assign_uploads({:images, field_options}, socket)

      assert %UploadConfig{name: :images} = socket.assigns.uploads.images
      assert socket.assigns.uploaded_files == [images: [{"old.png", "old.png"}]]
    end

    test "names the upload after its upload_key", %{field_options: field_options, socket: socket} do
      socket = Upload.assign_uploads({:images, Map.put(field_options, :upload_key, :pictures)}, socket)

      assert %UploadConfig{name: :pictures} = socket.assigns.uploads.pictures
      refute Map.has_key?(socket.assigns.uploads, :images)
    end

    test "sets no upload config for a readonly field but lists its files", %{
      field_options: field_options,
      socket: socket
    } do
      for readonly <- [true, fn assigns -> assigns.item.images != [] end] do
        socket = Upload.assign_uploads({:images, Map.put(field_options, :readonly, readonly)}, socket)

        refute Map.has_key?(socket.assigns, :uploads)
        assert socket.assigns.uploaded_files == [images: [{"old.png", "old.png"}]]
      end
    end

    test "labels the files with file_label", %{field_options: field_options, socket: socket} do
      field_options = Map.put(field_options, :file_label, &String.upcase/1)
      socket = Upload.assign_uploads({:images, field_options}, socket)

      assert socket.assigns.uploaded_files == [images: [{"old.png", "OLD.PNG"}]]

      html = render_assigned_form(socket, field_options, false)

      assert html =~ ~s(aria-label="Remove OLD.PNG")
      refute html =~ ~s(aria-label="Remove old.png")
    end

    test "configures an external upload with the external function", %{field_options: field_options, socket: socket} do
      presign_upload = fn _entry, socket -> {:ok, %{uploader: "S3"}, socket} end

      socket = Upload.assign_uploads({:images, Map.put(field_options, :external, presign_upload)}, socket)

      assert socket.assigns.uploads.images.external == presign_upload
    end

    test "configures an upload to the LiveView without external", %{field_options: field_options, socket: socket} do
      socket = Upload.assign_uploads({:images, field_options}, socket)

      assert socket.assigns.uploads.images.external == false
    end

    test "lists the files of a readonly field once on each update", %{field_options: field_options, socket: socket} do
      field = {:images, Map.put(field_options, :readonly, true)}

      socket = socket |> then(&Upload.assign_uploads(field, &1)) |> then(&Upload.assign_uploads(field, &1))

      assert socket.assigns.uploaded_files == [images: [{"old.png", "old.png"}]]
    end

    test "assigns the field's files once on every update", %{field_options: field_options, socket: socket} do
      field = {:images, field_options}
      socket = Upload.assign_uploads(field, Upload.assign_uploads(field, socket))

      assert socket.assigns.uploaded_files == [images: [{"old.png", "old.png"}]]
    end

    test "gives render_form/1 what it needs", %{field_options: field_options, socket: socket} do
      socket = Upload.assign_uploads({:images, field_options}, socket)
      html = render_assigned_form(socket, field_options, false)

      assert html =~ ~s(for="#{socket.assigns.uploads.images.ref}")
      assert html =~ "old.png"
    end

    test "renders a readonly field without a file input, drop target or remove button",
         %{field_options: field_options, socket: socket} do
      # A field that is readonly when the form opens gets no upload config. One that turns readonly later keeps it.
      for assign_options <- [Map.put(field_options, :readonly, true), field_options] do
        socket = Upload.assign_uploads({:images, assign_options}, socket)
        html = render_assigned_form(socket, Map.put(field_options, :readonly, true), true)

        assert html =~ "old.png"
        refute html =~ ~s(type="file")
        refute html =~ "phx-drop-target"
        refute html =~ "cancel-existing-entry"
      end
    end
  end

  describe "render_value/1" do
    test "labels the files with file_label" do
      field_options = %{module: Upload, list_existing_files: & &1.images, file_label: &String.upcase/1}

      html = render_component(&Upload.render_value/1, field: {:images, field_options}, item: %{images: ["old.png"]})

      assert html =~ "OLD.PNG"
      refute html =~ "old.png"
    end

    test "shows the file names without file_label" do
      field_options = %{module: Upload, list_existing_files: & &1.images}

      html = render_component(&Upload.render_value/1, field: {:images, field_options}, item: %{images: ["old.png"]})

      assert html =~ "old.png"
    end
  end

  describe "render_form/1" do
    setup do
      socket = Phoenix.LiveView.allow_upload(%Socket{}, :images, accept: :any, max_entries: 2)

      %{upload: socket.assigns.uploads.images}
    end

    test "shows Backpex's text for each upload error", %{upload: upload} do
      for {error, text} <- [
            {:too_large, "too large"},
            {:not_accepted, "unacceptable file type"},
            {:external_client_failure, "upload failed"},
            {{:external_metadata_failure, %{reason: :presign_failed}}, "upload could not be started"},
            {{:writer_failure, :enospc}, "upload failed"},
            {:unknown_error, "file could not be uploaded"}
          ] do
        html = render_upload_form(%{}, upload_with_errors(upload, [{"0", error}]))

        assert html =~ text, "expected #{inspect(text)} for #{inspect(error)}"
      end
    end

    test "shows Backpex's text for an error of the whole upload", %{upload: upload} do
      html = render_upload_form(%{}, upload_with_errors(upload, [{upload.ref, :too_many_files}]))

      assert html =~ "too many files"
    end

    test "shows the texts of the field module's upload_error/4", %{upload: upload} do
      field_options = %{module: ErrorTextsUpload, upload_key: :images}
      error = {:external_metadata_failure, %{reason: :quota}}

      html = render_upload_form(field_options, upload_with_errors(upload, [{"0", error}]))

      assert html =~ "refused: quota"
      refute html =~ "upload could not be started"

      html = render_upload_form(field_options, upload_with_errors(upload, [{upload.ref, :too_many_files}]))

      assert html =~ "at most 2 images"
      refute html =~ "too many files"

      html = render_upload_form(field_options, upload_with_errors(upload, [{"0", :too_large}]))

      assert html =~ "too large"
    end

    test "shows Backpex's texts for a field module without upload_error/4", %{upload: upload} do
      field_options = %{module: NamedFilesUpload, upload_key: :images}
      error = {:external_metadata_failure, %{reason: :quota}}

      html = render_upload_form(field_options, upload_with_errors(upload, [{"0", error}]))

      assert html =~ "upload could not be started"
    end

    test "lists the stored files before the new entries", %{upload: upload} do
      entries =
        for {ref, name} <- [{"0", "new-1.png"}, {"1", "new-2.png"}] do
          %UploadEntry{ref: ref, upload_ref: upload.ref, upload_config: :images, client_name: name}
        end

      uploaded_files = [{"old-1.png", "old-1.png"}, {"old-2.png", "old-2.png"}]
      html = render_upload_form(%{}, %{upload | entries: entries}, uploaded_files)

      assert html =~ ~r/old-1\.png.*old-2\.png.*new-1\.png.*new-2\.png/s
    end

    test "names the file in the labels of its cancel and remove buttons", %{upload: upload} do
      html = render_upload_form(%{}, upload_with_errors(upload, []), [{"uploads/abc123.png", "stored.png"}])

      assert html =~ ~s(aria-label="Cancel photo.png")
      assert html =~ ~s(aria-label="Remove stored.png")
      refute html =~ ~s(aria-label="Remove uploads/abc123.png")
    end

    test "renders a readonly field without an upload config" do
      html =
        render_component(&Upload.render_form/1,
          name: :images,
          field_options: %{module: Upload, label: "Images"},
          form: Phoenix.Component.to_form(%{}, as: :change),
          lv_uploads: %{},
          uploaded_files: [images: [{"old.png", "old.png"}]],
          live_resource: UntranslatedLive,
          readonly: true,
          type: :form
        )

      assert html =~ "Images"
      assert html =~ "old.png"
      refute html =~ ~s(type="file")
      refute html =~ "phx-drop-target"
      refute html =~ ~s(aria-label="Remove old.png")
    end
  end

  defp render_assigned_form(socket, field_options, readonly) do
    render_component(&Upload.render_form/1,
      name: :images,
      field_options: Map.put(field_options, :label, "Images"),
      form: Phoenix.Component.to_form(%{}, as: :change),
      lv_uploads: Map.get(socket.assigns, :uploads, %{}),
      uploaded_files: socket.assigns.uploaded_files,
      live_resource: UntranslatedLive,
      readonly: readonly,
      type: :form
    )
  end

  defp upload_with_errors(upload, errors) do
    entry = %UploadEntry{ref: "0", upload_ref: upload.ref, upload_config: :images, client_name: "photo.png"}

    %{upload | entries: [entry], errors: errors}
  end

  defp render_upload_form(field_options, upload, uploaded_files \\ []) do
    render_component(&Upload.render_form/1,
      name: :images,
      field_options: Map.merge(%{module: Upload, label: "Images"}, field_options),
      form: Phoenix.Component.to_form(%{}, as: :change),
      lv_uploads: %{images: upload},
      uploaded_files: [images: uploaded_files],
      live_resource: UntranslatedLive,
      readonly: false,
      type: :form
    )
  end
end
