defmodule DemoWeb.ResourceActions.Upload do
  @moduledoc false

  use Backpex.ResourceAction

  import Ecto.Changeset
  import Phoenix.LiveView

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
        consume: &consume_upload/3,
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

  defp upload_file_url(file_name) do
    static_path = Path.join([upload_static_dir(), file_name])
    Phoenix.VerifiedRoutes.static_url(DemoWeb.Endpoint, "/" <> static_path)
  end

  defp upload_file_name(entry) do
    [ext | _] = MIME.extensions(entry.client_type)
    "#{entry.uuid}.#{ext}"
  end

  # sobelow_skip ["Traversal"]
  defp consume_upload(socket, _resource, %{} = change) do
    consume_uploaded_entries(socket, :upload, fn %{path: path}, entry ->
      file_name = upload_file_name(entry)
      dest = Path.join([:code.priv_dir(:demo), "static", upload_static_dir(), file_name])
      File.cp!(path, dest)
      {:ok, upload_file_url(file_name)}
    end)

    case uploaded_entries(socket, :upload) do
      {[] = _completed, []} -> change
      {[entry | _] = _completed, []} -> Map.put(change, "upload", upload_file_name(entry))
    end
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
