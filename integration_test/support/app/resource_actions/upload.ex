defmodule Backpex.Test.ResourceActions.Upload do
  @moduledoc """
  A resource action with a required upload field. It doesn't store the file, it only shows a flash.
  """

  use Backpex.ResourceAction

  import Ecto.Changeset

  @impl Backpex.ResourceAction
  def title, do: "Upload file"

  @impl Backpex.ResourceAction
  def label, do: "Upload"

  @impl Backpex.ResourceAction
  def fields do
    [
      upload: %{
        module: Backpex.Fields.Upload,
        label: "Upload",
        upload_key: :upload,
        accept: ~w(.jpg .jpeg .png),
        max_entries: 1,
        put_upload_change: &put_upload_change/6,
        consume_upload: &consume_upload/4,
        remove_uploads: &remove_uploads/3,
        list_existing_files: &list_existing_files/1,
        type: :string
      },
      description: %{module: Backpex.Fields.Textarea, label: "Description", type: :string}
    ]
  end

  @impl Backpex.ResourceAction
  def changeset(change, attrs, _metadata) do
    change
    |> cast(attrs, [:upload, :description])
    |> validate_required([:upload, :description])
  end

  @impl Backpex.ResourceAction
  def handle(socket, _data) do
    {:ok, Phoenix.LiveView.put_flash(socket, :info, "File was uploaded successfully.")}
  end

  defp list_existing_files(_item), do: []

  defp put_upload_change(_socket, change, _item, uploaded_entries, _removed_entries, action) do
    entries =
      case action do
        :validate -> elem(uploaded_entries, 1)
        :insert -> elem(uploaded_entries, 0)
      end

    case entries do
      [entry | _rest] -> Map.put(change, "upload", file_name(entry))
      [] -> Map.put(change, "upload", "")
    end
  end

  defp consume_upload(_socket, _item, _meta, entry), do: {:ok, file_name(entry)}

  defp remove_uploads(_socket, _item, _removed_entries), do: :ok

  defp file_name(entry) do
    [ext | _tail] = MIME.extensions(entry.client_type)
    "#{entry.uuid}.#{ext}"
  end
end
