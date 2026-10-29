defmodule Backpex.Test.ProductLive do
  @moduledoc """
  Products with a multi-file upload field, a URL field with an `anchor_text`, a currency field, a range filter and an
  InlineCRUD field of an association (`short_links`).
  """
  use Backpex.LiveResource,
    adapter_config: [
      schema: Backpex.Test.Product,
      repo: Backpex.Test.Repo,
      update_changeset: &Backpex.Test.Product.changeset/3,
      create_changeset: &Backpex.Test.Product.changeset/3
    ]

  alias Backpex.LiveResource
  alias Backpex.Test.Endpoint
  alias Backpex.Test.Filters.ProductQuantityRange
  alias Backpex.Test.Layouts
  alias Backpex.Test.ShortLinkLive
  alias Backpex.Test.Uploads
  alias Phoenix.VerifiedRoutes

  @impl LiveResource
  def layout(_assigns), do: {Layouts, :admin}

  @impl LiveResource
  def singular_name, do: "Product"

  @impl LiveResource
  def plural_name, do: "Products"

  @impl LiveResource
  def filters do
    [
      quantity: %{module: ProductQuantityRange, label: "QTY"}
    ]
  end

  @impl LiveResource
  def fields do
    [
      images: %{
        module: Backpex.Fields.Upload,
        label: "Images",
        upload_key: :images,
        accept: ~w(.jpg .jpeg .png),
        max_entries: 2,
        max_file_size: 512_000,
        put_upload_change: &put_upload_change/6,
        consume_upload: &consume_upload/4,
        remove_uploads: &remove_uploads/3,
        list_existing_files: &list_existing_files/1,
        except: [:index]
      },
      name: %{module: Backpex.Fields.Text, label: "Name"},
      manufacturer: %{
        module: Backpex.Fields.URL,
        label: "Manufacturer URL",
        anchor_text: fn assigns -> "Visit " <> String.replace(URI.parse(assigns.value).host, ".com", "") end
      },
      quantity: %{module: Backpex.Fields.Number, label: "Quantity"},
      price: %{module: Backpex.Fields.Currency, label: "Price"},
      short_links: %{
        module: Backpex.Fields.InlineCRUD,
        label: "Short Links",
        type: :assoc,
        except: [:index],
        live_resource: ShortLinkLive,
        child_fields: [
          short_key: %{module: Backpex.Fields.Text, label: "URL Suffix"},
          url: %{module: Backpex.Fields.Text, label: "Target URL"}
        ]
      }
    ]
  end

  defp list_existing_files(%{images: images}) when is_list(images), do: images
  defp list_existing_files(_item), do: []

  defp put_upload_change(_socket, params, item, uploaded_entries, removed_entries, action) do
    new_entries =
      case action do
        :validate -> elem(uploaded_entries, 1)
        :insert -> elem(uploaded_entries, 0)
      end

    files = (list_existing_files(item) -- removed_entries) ++ Enum.map(new_entries, &file_name/1)

    Map.put(params, "images", files)
  end

  # sobelow_skip ["Traversal"]
  defp consume_upload(_socket, _item, %{path: path}, entry) do
    dest = Path.join([Uploads.dir(), upload_dir(), file_name(entry)])

    dest |> Path.dirname() |> File.mkdir_p!()
    File.cp!(path, dest)

    {:ok, VerifiedRoutes.static_url(Endpoint, "/" <> Path.join(upload_dir(), file_name(entry)))}
  end

  # sobelow_skip ["Traversal"]
  defp remove_uploads(_socket, _item, removed_entries) do
    for file <- removed_entries do
      [Uploads.dir(), upload_dir(), file] |> Path.join() |> File.rm!()
    end
  end

  defp file_name(entry) do
    [ext | _tail] = MIME.extensions(entry.client_type)
    "#{entry.uuid}.#{ext}"
  end

  defp upload_dir, do: Path.join(["uploads", "product", "images"])
end
