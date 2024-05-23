defmodule DemoWeb.ResourceActions.Upload do
  @moduledoc false

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
        accept: ~w(.jpg .jpeg),
        max_entries: 1,
        put_upload_change: &put_upload_change/3,
        consume_upload: &consume_upload/3,
        remove: &remove_upload/2,
        list_files: fn
          _item -> []
        end,
        type: :string
      },
      description: %{
        module: Backpex.Fields.Textarea,
        label: "Description",
        type: :string
      }
    ]
  end

  defp upload_static_dir, do: Path.join(["uploads", "user", "action"])

  defp upload_file_name(entry) do
    [ext | _] = MIME.extensions(entry.client_type)
    "#{entry.uuid}.#{ext}"
  end

  def put_upload_change(_socket, change, uploaded_entries) do
    case uploaded_entries do
      {[] = _completed, []} ->
        change

      {[entry | _] = _completed, []} ->
        Map.put(change, "upload", upload_file_name(entry))
    end
  end

  # sobelow_skip ["Traversal"]
  defp consume_upload(_socket, %{path: path} = _meta, entry) do
    file_name = upload_file_name(entry)
    dest = Path.join([:code.priv_dir(:demo), "static", upload_static_dir(), file_name])
    File.cp!(path, dest)
    :ok
  end

  defp remove_upload(_resource, _target), do: []

  @required_fields ~w[description]a

  @impl Backpex.ResourceAction
  def changeset(change, attrs, _metadata \\ []) do
    change
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
  end

  @impl Backpex.ResourceAction
  def handle(_socket, params) do
    if params["upload"] == nil do
      {:error, "No file uploaded."}
    else
      {:ok, "The file was uploaded successfully."}
    end
  end
end
