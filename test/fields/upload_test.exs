defmodule Backpex.Fields.UploadTest do
  use ExUnit.Case, async: true

  alias Backpex.Fields.Upload

  # An upload field that works out its files from the field instead of taking a function per field.
  defmodule NamedFilesUpload do
    def list_existing_files({name, _field_options} = _field, item), do: Map.get(item, name, [])
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
