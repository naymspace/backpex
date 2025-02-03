defmodule DemoWeb.ProductLive do
  use Backpex.LiveResource,
    adapter_config: [
      schema: Demo.Product,
      repo: Demo.Repo,
      update_changeset: &Demo.Product.changeset/3,
      create_changeset: &Demo.Product.changeset/3
    ],
    layout: {DemoWeb.Layouts, :admin},
    pubsub: [
      name: Demo.PubSub,
      topic: "products",
      event_prefix: "product_"
    ]

  import Ecto.Query, warn: false

  @impl Backpex.LiveResource
  def singular_name, do: "Product"

  @impl Backpex.LiveResource
  def plural_name, do: "Products"

  @impl Backpex.LiveResource
  def filters do
    [
      quantity: %{
        module: DemoWeb.Filters.ProductQuantityRange,
        label: "Quantity"
      }
    ]
  end

  @impl Backpex.LiveResource
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
        render: fn
          %{value: value} = assigns when is_list(value) ->
            ~H"""
            <div>
              <img :for={img <- @value} class="h-10 w-auto" src={file_url(img)} />
            </div>
            """

          assigns ->
            ~H"<p>{Backpex.HTML.pretty_value(@value)}</p>"
        end,
        except: [:index, :resource_action],
        align: :center
      },
      name: %{
        module: Backpex.Fields.Text,
        label: "Name",
        searchable: true
      },
      manufacturer: %{
        module: Backpex.Fields.URL,
        label: "Manufacturer URL",
        orderable: false
      },
      quantity: %{
        module: Backpex.Fields.Number,
        label: "Quantity",
        align: :center,
        translate_error: fn
          {_msg, [type: :integer, validation: :cast] = metadata} ->
            {"has to be a number", metadata}

          error ->
            error
        end,
        render: fn assigns ->
          ~H"""
          <p>{Number.Delimit.number_to_delimited(@value, precision: 0, delimiter: ".")}</p>
          """
        end
      },
      price: %{
        module: Backpex.Fields.Currency,
        label: "Price",
        align: :right
      },
      suppliers: %{
        module: Backpex.Fields.InlineCRUD,
        label: "Suppliers",
        type: :assoc,
        except: [:index],
        child_fields: [
          name: %{
            module: Backpex.Fields.Text,
            label: "Name"
          },
          url: %{
            module: Backpex.Fields.Text,
            label: "URL"
          }
        ]
      },
      short_links: %{
        module: Backpex.Fields.InlineCRUD,
        label: "Short Links",
        type: :assoc,
        except: [:index],
        child_fields: [
          short_key: %{
            module: Backpex.Fields.Text,
            label: "URL Suffix"
          },
          url: %{
            module: Backpex.Fields.Text,
            label: "Target URL"
          }
        ]
      }
    ]
  end

  @impl Backpex.LiveResource
  def metrics do
    [
      total_quantity: %{
        module: Backpex.Metrics.Value,
        label: "In Stock",
        class: "w-1/3",
        select: dynamic([i], sum(i.quantity)),
        format: fn value ->
          Integer.to_string(value) <> " Products"
        end
      }
    ]
  end

  defp list_existing_files(%{images: images} = _item) when is_list(images), do: images
  defp list_existing_files(_item), do: []

  defp put_upload_change(_socket, params, item, uploaded_entries, removed_entries, action) do
    existing_files = list_existing_files(item) -- removed_entries

    new_entries =
      case action do
        :validate ->
          elem(uploaded_entries, 1)

        :insert ->
          elem(uploaded_entries, 0)
      end

    files = existing_files ++ Enum.map(new_entries, fn entry -> file_name(entry) end)

    Map.put(params, "images", files)
  end

  # sobelow_skip ["Traversal"]
  defp consume_upload(_socket, _item, %{path: path} = _meta, entry) do
    file_name = file_name(entry)
    dest = Path.join([:code.priv_dir(:demo), "static", upload_dir(), file_name])

    File.cp!(path, dest)

    {:ok, file_url(file_name)}
  end

  # sobelow_skip ["Traversal"]
  defp remove_uploads(_socket, _item, removed_entries) do
    for file <- removed_entries do
      path = Path.join([:code.priv_dir(:demo), "static", upload_dir(), file])
      File.rm!(path)
    end
  end

  defp file_url(file_name) do
    static_path = Path.join([upload_dir(), file_name])
    Phoenix.VerifiedRoutes.static_url(DemoWeb.Endpoint, "/" <> static_path)
  end

  defp file_name(entry) do
    [ext | _tail] = MIME.extensions(entry.client_type)
    "#{entry.uuid}.#{ext}"
  end

  defp upload_dir, do: Path.join(["uploads", "product", "images"])
end
