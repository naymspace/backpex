defmodule Backpex.Fields.Upload do
  @config_schema [
    upload_key: [
      doc: "Required identifier for the upload field (the name of the upload).",
      type: :atom,
      required: true
    ],
    accept: [
      doc: "List of filetypes that will be accepted or `:any`.",
      type: {:or, [{:list, :string}, :atom]},
      default: :any
    ],
    max_entries: [
      doc: "Number of max files that can be uploaded.",
      type: :non_neg_integer,
      default: 1
    ],
    max_file_size: [
      doc: "Optional maximum file size in bytes to be allowed to uploaded.",
      type: :pos_integer,
      default: 8_000_000
    ],
    list_existing_files: [
      doc: """
      A function being used to display existing uploads. It has to return a list of all uploaded files as strings.
      Removed files during an edit of an item are automatically removed from the list.

      **Parameters**

      * `:item` (struct) - The item without its changes.

      **Example**

          def list_existing_files(item), do: item.files
      """,
      type: {:fun, 1},
      required: true
    ],
    file_label: [
      doc: """
      A function to be used to modify a file label of a single file. In the following example each file will have an
      `_upload` suffix.

      **Parameters**

      * `:file` (string) - The file.

      **Example**

          def file_label(file), do: file <> "_upload"
      """,
      type: {:fun, 1}
    ],
    consume_upload: [
      doc: """
      Required function to consume file uploads.
      A function to consume uploads. It is called after the item has been saved and is used to copy the files to a
      specific destination. Backpex will use this function as a callback for `consume_uploaded_entries`. See
      https://hexdocs.pm/phoenix_live_view/uploads.html#consume-uploaded-entries for more details.

      **Parameters**

      * `:socket` - The socket.
      * `:item` (struct) - The saved item (with its changes).
      * `:meta` - The upload meta.
      * `:entry` - The upload entry.

      **Example**

          defp consume_upload(_socket, _item, %{path: path} = _meta, entry) do
            file_name = ...
            file_url = ...
            static_dir = ...
            dest = Path.join([:code.priv_dir(:demo), "static", static_dir, file_name])

            File.cp!(path, dest)

            {:ok, file_url}
          end
      """,
      type: {:fun, 4},
      required: true
    ],
    put_upload_change: [
      doc: """
      A function to modify the params based on certain parameters. It is important because it ensures that file paths
      are added to the item change and therefore persisted in the database.

      **Parameters**

      * `:socket` - The socket.
      * `:params` (map) - The current params that will be passed to the changeset function.
      * `:item` (struct) - The item without its changes. On create will this will be an empty map.
      * `uploaded_entries` (tuple) - The completed and in progress entries for the upload.
      * `removed_entries` (list) - A list of removed uploads during edit.
      * `action` (atom) - The action (`:validate` or `:insert`)

      **Example**

          def put_upload_change(_socket, params, item, uploaded_entries, removed_entries, action) do
            existing_files = item.files -- removed_entries

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
      """,
      type: {:fun, 6},
      required: true
    ],
    remove_uploads: [
      doc: """
      A function that is being called after editing an item to be able to delete removed files.

      Note that this function is not invoked when an item is deleted. Therefore, you must implement file deletion logic in the `c:Backpex.LiveResource.on_item_deleted/2` callback.

      **Parameters**

      * `:socket` - The socket.
      * `:item` (struct) - The item without its changes.
      * `removed_entries` (list) - A list of removed uploads during edit. The list only contains files that existed before the edit.

      **Example**

          defp remove_uploads(_socket, _item, removed_entries) do
            for file <- removed_entries do
              file_path = ...
              File.rm!(file_path)
            end
          end
      """,
      type: {:fun, 3},
      required: true
    ],
    external: [
      doc: """
      A 2-arity function that allows the server to generate metadata for each upload entry.

      **Parameters**

      * `:entry` - The upload entry.
      * `:socket` - The socket.

      **Examples**

      This is an example for S3-Compatible object storage, for more examples check the Phoenix LiveView
      documentation for [External Uploads](https://hexdocs.pm/phoenix_live_view/external-uploads.html).

          defp presign_upload(entry, socket) do
            config = ExAws.Config.new(:s3)
            key = "uploads/example/" <> entry.client_name

            {:ok, url} =
              ExAws.S3.presigned_url(config, :put, @bucket, key,
                expires_in: 3600,
                query_params: [{"Content-Type", entry.client_type}]
              )

            meta = %{uploader: "S3", key: key, url: url}
            {:ok, meta, socket}
          end

      """,
      type: {:fun, 2},
      required: false
    ]
  ]

  @moduledoc """
  A field for handling uploads.

  > #### Warning {: .warning}
  >
  > This field does **not** currently support using a custom `Phoenix.LiveView.UploadWriter`.

  ## Field-specific options

  See `Backpex.Field` for general field options.

  The `upload_key`, `accept`, `max_entries` and `max_file_size` options are forwarded to
  https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html#allow_upload/3. See the documentation for more information.

  #{NimbleOptions.docs(@config_schema)}

  > #### Info {: .info}
  >
  > The first two examples copy uploads to a static folder in the application. In a production environment,
  you should consider uploading files to an appropriate object store.

  ## Full Single File Example

  In this example we are adding an avatar upload for a user. We implement it so that exactly one avatar must exist.

      defmodule Demo.Repo.Migrations.AddAvatarToUsers do
        use Ecto.Migration

        def change do
          alter table(:users) do
            add(:avatar, :string, null: false, default: "")
          end
        end
      end

      defmodule Demo.User do
        use Ecto.Schema

        schema "users" do
          field(:avatar, :string, default: "")
          ...
        end

        def changeset(user, attrs, _metadata \\ []) do
          user
          |> cast(attrs, [:avatar])
          |> validate_required([:avatar])
          |> validate_change(:avatar, fn
            :avatar, "too_many_files" ->
              [avatar: "has to be exactly one"]

            :avatar, "" ->
              [avatar: "can't be blank"]

            :avatar, _avatar ->
              []
          end)
        end
      end

      defmodule DemoWeb.UserLive do
        use Backpex.LiveResource,
          ...

        @impl Backpex.LiveResource
        def fields do
          [
            avatar: %{
              module: Backpex.Fields.Upload,
              label: "Avatar",
              upload_key: :avatar,
              accept: ~w(.jpg .jpeg .png),
              max_file_size: 512_000,
              put_upload_change: &put_upload_change/6,
              consume_upload: &consume_upload/4,
              remove_uploads: &remove_uploads/3,
              list_existing_files: &list_existing_files/1,
              render: fn
                %{value: value} = assigns when value == "" or is_nil(value) ->
                  ~H"<p><%= Backpex.HTML.pretty_value(@value) %></p>"

                assigns ->
                  ~H'<img class="h-10 w-auto" src={file_url(@value)} />'
              end
            },
            ...
          ]
        end

        defp list_existing_files(%{avatar: avatar} = _item) when avatar != "" and not is_nil(avatar), do: [avatar]
        defp list_existing_files(_item), do: []

        def put_upload_change(_socket, params, item, uploaded_entries, removed_entries, action) do
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
              Map.put(params, "avatar", file)

            [_file | _other_files] ->
              Map.put(params, "avatar", "too_many_files")

            [] ->
              Map.put(params, "avatar", "")
          end
        end

        defp consume_upload(_socket, _item, %{path: path} = _meta, entry) do
          file_name = file_name(entry)
          dest = Path.join([:code.priv_dir(:demo), "static", upload_dir(), file_name])

          File.cp!(path, dest)

          {:ok, file_url(file_name)}
        end

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
          [ext | _] = MIME.extensions(entry.client_type)
          entry.uuid <> "." <> ext
        end

        defp upload_dir, do: Path.join(["uploads", "user", "avatar"])
      end

  ## Full Multi File Example

  In this example, we are adding images to a product resource. We limit the images to a maximum of 2.

      defmodule Demo.Repo.Migrations.AddImagesToProducts do
        use Ecto.Migration

        def change do
          alter table(:products) do
            add(:images, {:array, :string})
          end
        end
      end

      defmodule Demo.Product do
        use Ecto.Schema

        schema "products" do
          field(:images, {:array, :string})
          ...
        end

        def changeset(user, attrs, _metadata \\ []) do
          user
          |> cast(attrs, [:images])
          |> validate_length(:images, max: 2)
        end
      end

      defmodule DemoWeb.ProductLive do
        use Backpex.LiveResource,
          ...

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
                  ~H'''
                  <div>
                    <img :for={img <- @value} class="h-10 w-auto" src={file_url(img)} />
                  </div>
                  '''

                assigns ->
                  ~H'<p><%= Backpex.HTML.pretty_value(@value) %></p>'
              end,
              except: [:index, :resource_action],
              align_label: :center
            },
            ...
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

        defp consume_upload(_socket, _item, %{path: path} = _meta, entry) do
          file_name = file_name(entry)
          dest = Path.join([:code.priv_dir(:demo), "static", upload_dir(), file_name])

          File.cp!(path, dest)

          {:ok, file_url(file_name)}
        end

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
          [ext | _] = MIME.extensions(entry.client_type)
          entry.uuid <> "." <> ext
        end

        defp upload_dir, do: Path.join(["uploads", "product", "images"])
      end

  ## Full External File Example

  In this example we are adding an avatar upload for a user and storing it in an external object storage like S3 or R2
  This example works with Cloudflare R2 and assumes that you configured `ExAws` and `ExAws.S3` correctly and that you're
  serving the images from a CDN in front of your object storage.

  For more details check the Phoenix LiveView documentation for [External Uploads](https://hexdocs.pm/phoenix_live_view/external-uploads.html).

      defmodule Demo.Repo.Migrations.AddAvatarToUsers do
        use Ecto.Migration

        def change do
          alter table(:users) do
            add(:avatar, :string)
          end
        end
      end

      defmodule Demo.User do
        use Ecto.Schema

        schema "users" do
          field(:avatar, :string)
          ...
        end

        def changeset(user, attrs, _metadata \\ []) do
          user
          |> cast(attrs, [:avatar])
          |> validate_change(:avatar, fn
            :avatar, "too_many_files" ->
              [avatar: "has to be exactly one"]

            :avatar, "" ->
              [avatar: "can't be blank"]

            :avatar, _avatar ->
              []
          end)
        end
      end

      defmodule DemoWeb.UserLive do
        use Backpex.LiveResource,
          ...

        @base_cdn_path "https://cdn.example.com/"
        @upload_path "uploads/backpex/"
        @bucket "example"
        @base_r2_host "https://my_host.r2.cloudflarestorage.com/"

        @impl Backpex.LiveResource
        def fields do
          [
            avatar: %{
              module: Backpex.Fields.Upload,
              label: "Avatar",
              upload_key: :avatar,
              accept: ~w(.jpg .jpeg .png),
              max_file_size: 512_000,
              put_upload_change: &put_upload_change/6,
              consume_upload: &consume_upload/4,
              remove_uploads: &remove_uploads/3,
              list_existing_files: &list_existing_files/1,
              external: &presign_upload/2,
              render: fn
                %{value: value} = assigns when value == "" or is_nil(value) ->
                  ~H"<p>{Backpex.HTML.pretty_value(@value)}</p>"

                assigns ->
                  ~H'<img class="h-10 w-auto" src={@value} />'
              end
            },
            ...
          ]
        end

        defp list_existing_files(%{avatar: avatar} = _item) when avatar != "" and not is_nil(avatar), do: [avatar]
        defp list_existing_files(_item), do: []

        defp presign_upload(entry, socket) do
          config = ExAws.Config.new(:s3)
          key = @upload_path <> entry.client_name

          {:ok, url} =
            ExAws.S3.presigned_url(config, :put, @bucket, key,
              expires_in: 3600,
              query_params: [{"Content-Type", entry.client_type}]
          )

          meta = %{uploader: "S3", key: key, url: url}

          {:ok, meta, socket}
        end

        def put_upload_change(_socket, params, item, uploaded_entries, removed_entries, action) do
          existing_files = list_existing_files(item) -- removed_entries

          new_entries =
            case action do
              :validate ->
                elem(uploaded_entries, 1)

              :insert ->
                elem(uploaded_entries, 0)
            end

          files = existing_files ++ Enum.map(new_entries, fn entry -> entry.client_name end)

          case files do
            [file] ->
              file_path = @base_cdn_path <> @upload_path <> file
              Map.put(params, "avatar", file_path)

            [_file | _other_files] ->
              Map.put(params, "avatar", "too_many_files")

            [] ->
              Map.put(params, "avatar", "")
          end
        end

        defp consume_upload(_socket, _item, _meta, _entry) do
          {:ok, :external}
        end

        defp remove_uploads(_socket, _item, removed_entries) do
          for file <- removed_entries do
            object = String.replace_prefix(file, @base_cdn_path, "")
            ExAws.S3.delete_object(@bucket, object) |> ExAws.request!()
          end
        end
      end

  You also need to create an `Uploader` in the `app.js` file to handle the actual upload

      let Uploaders = {}

      Uploaders.S3 = function (entries, onViewError) {
        entries.forEach(entry => {
          let xhr = new XMLHttpRequest()
          onViewError(() => xhr.abort())
          xhr.onload = () => xhr.status === 200 ? entry.progress(100) : entry.error()
          xhr.onerror = () => entry.error()

          xhr.upload.addEventListener("progress", (event) => {
            if(event.lengthComputable){
              let percent = Math.round((event.loaded / event.total) * 100)
              if(percent < 100){ entry.progress(percent) }
            }
          })

          let url = entry.meta.url
          xhr.open("PUT", url, true)
          xhr.send(entry.file)
        })
      }

      let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
      let liveSocket = new LiveSocket("/live", Socket, {
        uploaders: Uploaders,
        ...
      })

  """
  use Backpex.Field, config_schema: @config_schema
  alias Backpex.HTML.Form, as: BackpexForm
  require Backpex

  @impl Backpex.Field
  def render_value(assigns) do
    %{field: field, item: item} = assigns

    uploaded_files = existing_file_paths(field, item, [])

    assigns = assign(assigns, :uploaded_files, uploaded_files)

    ~H"""
    <div class="flex flex-col">
      <p :for={{_file_key, label} <- @uploaded_files} class="break-all">
        {label}
      </p>
    </div>
    """
  end

  @impl Backpex.Field
  def render_form(assigns) do
    upload_key = assigns.field_options.upload_key
    uploads_allowed = not is_nil(assigns.lv_uploads[upload_key])
    translate_error_fun = Map.get(assigns.field_options, :translate_error, &Function.identity/1)

    hidden_field_name = to_string(assigns.name)
    upload_used_input = Map.get(assigns.form.params, hidden_field_name <> "_used_input")
    used_input? = upload_used_input not in [nil, "false"]

    errors =
      if used_input? do
        assigns.form[assigns.name].errors
      else
        if Phoenix.Component.used_input?(assigns.form[assigns.name]), do: assigns.form[assigns.name].errors, else: []
      end

    form_errors = BackpexForm.translate_form_errors(errors, translate_error_fun)

    assigns =
      assigns
      |> assign(:used_input?, to_string(used_input?))
      |> assign(:hidden_field_name, hidden_field_name)
      |> assign(:upload, assigns.lv_uploads[upload_key])
      |> assign(:upload_key, upload_key)
      |> assign(:uploads_allowed, uploads_allowed)
      |> assign(:uploaded_files, Keyword.get(assigns.uploaded_files, upload_key))
      |> assign(:errors, errors)
      |> assign(:form_errors, form_errors)

    ~H"""
    <div>
      <Layout.field_container>
        <:label align={Backpex.Field.align_label(@field_options, assigns, :top)}>
          <Layout.input_label text={@field_options[:label]} />
        </:label>
        <div
          id={"#{@name}-drop-target"}
          class="w-full max-w-lg"
          phx-hook="BackpexDragHover"
          phx-drop-target={if @uploads_allowed, do: @upload.ref}
        >
          <div class={[
            "rounded-field flex justify-center border-2 border-dashed px-6 pt-5 pb-6",
            @errors == [] && "border-base-content/25",
            @errors != [] && "border-error bg-error/10"
          ]}>
            <div class="flex flex-col items-center space-y-1 text-center">
              <Backpex.HTML.CoreComponents.icon name="hero-document-arrow-up" class="text-base-content/50 h-8 w-8" />
              <div class="flex text-sm">
                <label>
                  <a class="link link-hover link-primary font-medium">
                    {Backpex.__("Upload a file", @live_resource)}
                  </a>
                  <.live_file_input :if={@uploads_allowed} upload={@upload} phx-target="#form-component" class="hidden" />
                </label>
                <input
                  type="hidden"
                  name={"change[#{@hidden_field_name}_used_input]"}
                  id={"change_#{@hidden_field_name}_used_input"}
                  value={@used_input?}
                  data-upload-key={@upload_key}
                  phx-hook="BackpexCancelEntry"
                />
                <p class="pl-1">{Backpex.__("or drag and drop", @live_resource)}</p>
              </div>
            </div>
          </div>
        </div>

        <section class="mt-2">
          <article>
            <%= if @uploads_allowed do %>
              <div :for={entry <- @upload.entries} class="break-all">
                <p class="inline">{Map.get(entry, :client_name)}</p>
                <button
                  type="button"
                  phx-click="cancel-entry"
                  phx-value-ref={entry.ref}
                  phx-value-id={@upload_key}
                  phx-target="#form-component"
                  class="cursor-pointer"
                >
                  &times;
                </button>
                <progress :if={entry.progress > 0} class="progress ml-4 w-32" value={entry.progress} max="100"></progress>
                <p :for={err <- upload_errors(@upload, entry)} class="text-xs italic text-red-500">
                  {error_to_string(err, @live_resource)}
                </p>
              </div>
            <% end %>

            <%= if @type == :form do %>
              <div :for={{file_key, label} <- @uploaded_files} class="break-all">
                <p class="inline">{label}</p>
                <button
                  type="button"
                  phx-click="cancel-existing-entry"
                  phx-value-ref={file_key}
                  phx-value-id={@upload_key}
                  phx-target="#form-component"
                  class="cursor-pointer"
                >
                  &times;
                </button>
              </div>
            <% end %>
          </article>

          <%= if @uploads_allowed do %>
            <p :for={err <- upload_errors(@upload)} class="text-xs italic text-red-500">
              {error_to_string(err, @live_resource)}
            </p>
          <% end %>
          <BackpexForm.error :for={msg <- @form_errors}>{msg}</BackpexForm.error>

          <%= if help_text = Backpex.Field.help_text(@field_options, assigns) do %>
            <Backpex.HTML.Form.help_text class="mt-1">{help_text}</Backpex.HTML.Form.help_text>
          <% end %>
        </section>
      </Layout.field_container>
    </div>
    """
  end

  @impl Backpex.Field
  def assign_uploads({_name, field_options} = field, socket) do
    field_files = {field_options.upload_key, existing_file_paths(field, socket.assigns.item, [])}

    max_entries = field_options.max_entries
    max_file_size = Map.get(field_options, :max_file_size, 8_000_000)

    if get_in(socket.assigns, [:uploads, field_options.upload_key]) do
      socket
    else
      socket
      |> assign_uploaded_files(field_files)
      |> allow_field_uploads(field_options, max_entries, max_file_size)
    end
  end

  defp assign_uploaded_files(socket, field_files) do
    uploaded_files = Map.get(socket.assigns, :uploaded_files, [])
    assign(socket, :uploaded_files, [field_files | uploaded_files])
  end

  defp allow_field_uploads(socket, _field_options, 0, _max_file_size), do: socket

  defp allow_field_uploads(
         socket,
         %{external: presign_upload} = field_options,
         max_entries,
         max_file_size
       ) do
    Phoenix.LiveView.allow_upload(socket, field_options.upload_key,
      accept: field_options.accept,
      max_entries: max_entries,
      max_file_size: max_file_size,
      external: presign_upload
    )
  end

  defp allow_field_uploads(socket, field_options, max_entries, max_file_size) do
    Phoenix.LiveView.allow_upload(socket, field_options.upload_key,
      accept: field_options.accept,
      max_entries: max_entries,
      max_file_size: max_file_size
    )
  end

  @doc """
  Returns a list of existing files mapped to a label.
  """
  def existing_file_paths(field, item, removed_files) do
    files = list_existing_files(field, item, removed_files)

    map_file_paths(field, files)
  end

  @doc """
  Lists existing files based on item and list of removed files.
  """
  def list_existing_files({_field_name, field_options} = _field, item, removed_files) do
    %{list_existing_files: list_existing_files} = field_options

    list_existing_files.(item) -- removed_files
  end

  @doc """
  Maps uploaded files to keyword list with identifier and label.
  """
  def map_file_paths({_field_name, field_options} = _field, files) when is_list(files) do
    files
    |> Enum.map(&{&1, label_from_file(field_options, &1)})
  end

  @doc """
  Calls field option function to get label from filename. Defaults to filename.

  ## Examples

      iex> Backpex.Fields.Upload.label_from_file(%{file_label: fn file -> file <> "xyz" end}, "file")
      "filexyz"
      iex> Backpex.Fields.Upload.label_from_file(%{}, "file")
      "file"
  """
  def label_from_file(%{file_label: file_label} = _field_options, file), do: file_label.(file)
  def label_from_file(_field_options, file), do: file

  defp error_to_string(:too_large, live_resource), do: Backpex.__("too large", live_resource)
  defp error_to_string(:too_many_files, live_resource), do: Backpex.__("too many files", live_resource)
  defp error_to_string(:not_accepted, live_resource), do: Backpex.__("unacceptable file type", live_resource)
end
