defmodule Backpex.Test.SampleFieldOptionsLive do
  @moduledoc """
  A LiveResource of samples whose fields set options that `Backpex.Test.SampleLive` leaves at their defaults: `readonly`
  of `Backpex.Fields.Checkgroup` and `external` of `Backpex.Fields.Upload`.

  The upload goes to a pretend object storage: `presign_upload/2` returns the metadata a client uploader would use, and
  `consume_upload/4` only accepts that metadata, so the save fails if the upload was not external.
  """
  use Backpex.LiveResource,
    adapter_config: [
      schema: Backpex.Test.Sample,
      repo: Backpex.Test.Repo,
      update_changeset: &Backpex.Test.Sample.changeset/3,
      create_changeset: &Backpex.Test.Sample.changeset/3
    ]

  @impl Backpex.LiveResource
  def layout(_assigns), do: {Backpex.Test.Layouts, :admin}

  @impl Backpex.LiveResource
  def singular_name, do: "Sample"

  @impl Backpex.LiveResource
  def plural_name, do: "Samples"

  @impl Backpex.LiveResource
  def fields do
    [
      text: %{module: Backpex.Fields.Text, label: "Text"},
      checkgroup: %{
        module: Backpex.Fields.Checkgroup,
        label: "Checkgroup",
        options: [{"Read", "read"}, {"Write", "write"}],
        readonly: true
      },
      upload: %{
        module: Backpex.Fields.Upload,
        label: "Upload",
        upload_key: :upload,
        accept: ~w(.txt),
        max_entries: 1,
        external: &presign_upload/2,
        put_upload_change: &put_upload_change/6,
        consume_upload: &consume_upload/4,
        remove_uploads: &remove_uploads/3,
        list_existing_files: &list_existing_files/1
      }
    ]
  end

  defp presign_upload(entry, socket) do
    key = "samples/" <> entry.client_name

    {:ok, %{uploader: "TestStorage", key: key, url: "https://storage.example/" <> key}, socket}
  end

  defp list_existing_files(%{upload: upload}) when upload not in [nil, ""], do: [upload]
  defp list_existing_files(_item), do: []

  defp put_upload_change(_socket, params, item, uploaded_entries, removed_entries, action) do
    new_entries =
      case action do
        :validate -> elem(uploaded_entries, 1)
        :insert -> elem(uploaded_entries, 0)
      end

    case (list_existing_files(item) -- removed_entries) ++ Enum.map(new_entries, &("samples/" <> &1.client_name)) do
      [] -> Map.put(params, "upload", nil)
      [file | _rest] -> Map.put(params, "upload", file)
    end
  end

  defp consume_upload(_socket, _item, %{uploader: "TestStorage", key: key}, _entry), do: {:ok, key}

  defp remove_uploads(_socket, _item, _removed_entries), do: :ok
end
