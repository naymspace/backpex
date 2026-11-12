defmodule Backpex.Test.SampleLive do
  @moduledoc """
  A LiveResource with one field of every scalar field type. The accessibility browser tests audit every field type in
  every view through it.
  """
  use Backpex.LiveResource,
    adapter_config: [
      schema: Backpex.Test.Sample,
      repo: Backpex.Test.Repo,
      update_changeset: &Backpex.Test.Sample.changeset/3,
      create_changeset: &Backpex.Test.Sample.changeset/3
    ]

  alias Backpex.Test.Uploads

  @impl Backpex.LiveResource
  def layout(_assigns), do: {Backpex.Test.Layouts, :admin}

  @impl Backpex.LiveResource
  def singular_name, do: "Sample"

  @impl Backpex.LiveResource
  def plural_name, do: "Samples"

  @impl Backpex.LiveResource
  def fields do
    [
      text: %{module: Backpex.Fields.Text, label: "Text", searchable: true},
      textarea: %{module: Backpex.Fields.Textarea, label: "Textarea"},
      number: %{module: Backpex.Fields.Number, label: "Number"},
      boolean: %{module: Backpex.Fields.Boolean, label: "Boolean"},
      select: %{
        module: Backpex.Fields.Select,
        label: "Select",
        options: [One: "one", Two: "two", Three: "three"],
        prompt: "Choose one"
      },
      multi_select: %{
        module: Backpex.Fields.MultiSelect,
        label: "Multi Select",
        options: fn _assigns -> [{"Red", "red"}, {"Green", "green"}, {"Blue", "blue"}] end
      },
      checkgroup: %{
        module: Backpex.Fields.Checkgroup,
        label: "Checkgroup",
        options: [{"Read", "read"}, {"Write", "write"}]
      },
      date: %{module: Backpex.Fields.Date, label: "Date"},
      date_time: %{module: Backpex.Fields.DateTime, label: "Date Time"},
      time: %{module: Backpex.Fields.Time, label: "Time"},
      email: %{module: Backpex.Fields.Email, label: "Email"},
      url: %{module: Backpex.Fields.URL, label: "URL"},
      currency: %{module: Backpex.Fields.Currency, label: "Currency"},
      upload: %{
        module: Backpex.Fields.Upload,
        label: "Upload",
        upload_key: :upload,
        accept: ~w(.txt .png),
        max_entries: 1,
        put_upload_change: &put_upload_change/6,
        consume_upload: &consume_upload/4,
        remove_uploads: &remove_uploads/3,
        list_existing_files: &list_existing_files/1
      },
      category: %{
        module: Backpex.Fields.BelongsTo,
        label: "Category",
        display_field: :name,
        live_resource: Backpex.Test.CategoryLive,
        prompt: "Choose a category"
      }
    ]
  end

  defp list_existing_files(%{upload: upload}) when upload not in [nil, ""], do: [upload]
  defp list_existing_files(_item), do: []

  defp put_upload_change(_socket, params, item, uploaded_entries, removed_entries, action) do
    new_entries =
      case action do
        :validate -> elem(uploaded_entries, 1)
        :insert -> elem(uploaded_entries, 0)
      end

    case (list_existing_files(item) -- removed_entries) ++ Enum.map(new_entries, &file_name/1) do
      [] -> Map.put(params, "upload", nil)
      [file | _rest] -> Map.put(params, "upload", file)
    end
  end

  defp consume_upload(_socket, _item, %{path: path}, entry) do
    dest = Path.join([Uploads.dir(), "uploads", "samples", file_name(entry)])
    dest |> Path.dirname() |> File.mkdir_p!()
    File.cp!(path, dest)

    {:ok, "/uploads/samples/" <> file_name(entry)}
  end

  defp remove_uploads(_socket, _item, removed_entries) do
    Enum.each(removed_entries, &File.rm(Path.join([Uploads.dir(), "uploads", "samples", &1])))
  end

  defp file_name(entry) do
    [ext | _rest] = MIME.extensions(entry.client_type)
    "#{entry.uuid}.#{ext}"
  end
end
