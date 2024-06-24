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
        accept: ~w(.jpg .jpeg .png),
        max_entries: 1,
        put_upload_change: &put_upload_change/6,
        consume_upload: &consume_upload/5,
        remove_uploads: &remove_uploads/3,
        list_existing_files: &list_existing_files/1,
        type: :string
      },
      description: %{
        module: Backpex.Fields.Textarea,
        label: "Description",
        type: :string
      }
    ]
  end

  @required_fields ~w[description upload]a

  @impl Backpex.ResourceAction
  def changeset(change, attrs, _metadata \\ []) do
    change
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
    |> validate_length(:upload, min: 1)
    |> validate_change(:upload, fn
      :upload, "too_many_files" ->
        [upload: "has to be exactly one"]

      :upload, "" ->
        [upload: "can't be blank"]

      :upload, _avatar ->
        []
    end)
  end

  @impl Backpex.ResourceAction
  def handle(_socket, _params), do: {:ok, "File was uploaded successfully."}

  defp list_existing_files(_item), do: []

  def put_upload_change(_socket, change, item, uploaded_entries, removed_entries, action) do
    existing_files = list_existing_files(item) -- removed_entries

    new_entries =
      case action do
        :validate ->
          elem(uploaded_entries, 1)

        :insert ->
          elem(uploaded_entries, 0)
      end

    files = existing_files ++ Enum.map(new_entries, fn entry -> file_name(entry) end)

    case files do
      [file] ->
        Map.put(change, "upload", file)

      [_file | _other_files] ->
        Map.put(change, "upload", "too_many_files")

      [] ->
        Map.put(change, "upload", "")
    end
  end

  defp consume_upload(_socket, _item, _change, _meta, entry) do
    file_name = file_name(entry)

    # Copy file to destination
    # dest = Path.join([:code.priv_dir(:demo), "static", upload_dir(), file_name])
    # File.cp!(path, dest)

    {:ok, file_url(file_name)}
  end

  defp remove_uploads(_socket, _item, _removed_entries), do: :ok

  defp file_url(file_name) do
    static_path = Path.join([upload_dir(), file_name])
    Phoenix.VerifiedRoutes.static_url(DemoWeb.Endpoint, "/" <> static_path)
  end

  defp file_name(entry) do
    [ext | _] = MIME.extensions(entry.client_type)
    "#{entry.uuid}.#{ext}"
  end

  defp upload_dir, do: Path.join(["uploads", "product", "images"])
end
