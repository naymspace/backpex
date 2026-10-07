defmodule Backpex.Fields.UploadTest do
  use ExUnit.Case, async: true

  alias Backpex.Field
  alias Backpex.Fields.Upload

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
end
