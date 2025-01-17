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
      A function that is being called after saving an item to be able to delete removed files.

      **Parameters**

      * `:socket` - The socket.
      * `:item` (struct) - The item without its changes.
      * `removed_entries` (list) - A list of removed uploads during edit.

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
    ]
  ]

  @moduledoc """
  A field for handling uploads.

  > #### Warning {: .warning}
  >
  > This field does **not** currently support `Phoenix.LiveView.UploadWriter` and direct / external uploads.

  ## Field-specific options

  See `Backpex.Field` for general field options.

  The `upload_key`, `accept`, `max_entries` and `max_file_size` options are forwarded to
  https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html#allow_upload/3. See the documentation for more information.

  #{NimbleOptions.docs(@config_schema)}

  > #### Info {: .info}
  >
  > The following examples copy uploads to a static folder in the application. In a production environment, you should
  consider uploading files to an appropriate object store.

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
              align: :center
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
  """
  use Backpex.Field, config_schema: @config_schema
  alias Backpex.HTML.Form, as: BackpexForm

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
    uploads_allowed = not is_nil(assigns.field_uploads)
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
      |> assign(:upload_key, upload_key)
      |> assign(:uploads_allowed, uploads_allowed)
      |> assign(:uploaded_files, Keyword.get(assigns.uploaded_files, upload_key))
      |> assign(:errors, errors)
      |> assign(:form_errors, form_errors)

    ~H"""
    <div x-data="{
        dispatchChangeEvent(el) {
          $nextTick(
            () => {
              form = document.getElementById('resource-form');
              if (form) el.dispatchEvent(new Event('input', { bubbles: true }));
            }
          )
        }
      }">
      <Layout.field_container>
        <:label align={Backpex.Field.align_label(@field_options, assigns, :top)}>
          <Layout.input_label text={@field_options[:label]} />
        </:label>
        <div
          x-data="{dragging: 0}"
          x-on:dragenter="dragging++"
          x-on:dragleave="dragging--"
          x-on:drop="dragging = 0"
          class="w-full max-w-lg"
          phx-drop-target={if @uploads_allowed, do: @field_uploads.ref}
        >
          <div
            class={[
              "rounded-btn flex justify-center border-2 border-dashed px-6 pt-5 pb-6",
              @errors == [] && "border-base-content/25",
              @errors != [] && "border-error bg-error/10"
            ]}
            x-bind:class="dragging > 0 ? 'border-primary' : 'border-base-content/25'"
          >
            <div class="flex flex-col items-center space-y-1 text-center">
              <Backpex.HTML.CoreComponents.icon name="hero-document-arrow-up" class="text-base-content/50 h-8 w-8" />
              <div class="flex text-sm">
                <label>
                  <a class="link link-hover link-primary font-medium">
                    {Backpex.translate("Upload a file")}
                  </a>
                  <.live_file_input
                    :if={@uploads_allowed}
                    upload={@field_uploads}
                    phx-target="#form-component"
                    class="hidden"
                  />
                </label>
                <input
                  type="hidden"
                  name={"change[#{@hidden_field_name}_used_input]"}
                  id={"change_#{@hidden_field_name}_used_input"}
                  value={@used_input?}
                />
                <p class="pl-1">{Backpex.translate("or drag and drop")}</p>
              </div>
            </div>
          </div>
        </div>

        <section class="mt-2">
          <article>
            <%= if @uploads_allowed do %>
              <div :for={entry <- @field_uploads.entries} class="break-all">
                <p class="inline">{Map.get(entry, :client_name)}</p>

                <button
                  type="button"
                  phx-click="cancel-entry"
                  phx-value-ref={entry.ref}
                  phx-value-id={@upload_key}
                  phx-target="#form-component"
                  @click="() => dispatchChangeEvent($el)"
                >
                  &times;
                </button>

                <p :for={err <- upload_errors(@field_uploads, entry)} class="text-xs italic text-red-500">
                  {error_to_string(err)}
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
                  @click="() => dispatchChangeEvent($el)"
                >
                  &times;
                </button>
              </div>
            <% end %>
          </article>

          <%= if @uploads_allowed do %>
            <p :for={err <- upload_errors(@field_uploads)} class="text-xs italic text-red-500">
              {error_to_string(err)}
            </p>
          <% end %>
          <BackpexForm.error :for={msg <- @form_errors}>{msg}</BackpexForm.error>
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

  defp error_to_string(:too_large), do: Backpex.translate("too large")
  defp error_to_string(:too_many_files), do: Backpex.translate("too many files")
  defp error_to_string(:not_accepted), do: Backpex.translate("unacceptable file type")
end
