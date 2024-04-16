defmodule Backpex.Fields.Upload do
  @moduledoc ~S"""
  A field for handling an upload.

  > #### Warning {: .warning}
  >
  > This field is in beta state. Use at your own risk.

  ## Options

    * `:upload_key` - Required identifier for the upload field.
    * `:accept` - Required filetypes that will be accepted.
    * `:max_entries` - Required number of max files that can be uploaded.
    * `:max_file_size` - Optional maximum file size in bytes to be allowed to uploaded. Defaults 8 MB (`8_000_000`).
    * `:list_files` - Required function that returns a list of all uploaded files.
    * `:file_label` - Optional function to get the label of a single file.
    * `:consume` - Required function to consume file uploads and handle changes in the item before it is saved (e.g. append file paths).
    * `:remove` - Required function to remove a specific file.

  ## Example

  ### Single File

      @impl Backpex.LiveResource
      def fields do
      [
        avatar: %{
          module: Backpex.Fields.Upload,
          label: "Avatar",
          upload_key: :avatar,
          accept: ~w(.jpg .jpeg),
          max_entries: 1,
          max_file_size: 12_000_000,
          consume: &consume_avatar/3,
          remove: &remove_avatar/2,
          list_files: &list_files_avatar/1,
          render: fn
            %{value: ""} = assigns -> ~H"<%= Backpex.HTML.pretty_value(@value) %>"
            assigns -> ~H'<img class="w-5 h-5 rounded-full" src={avatar_file_url(@value)} />'
          end
        },
      ]
      end

      defp avatar_static_dir, do: Path.join(["uploads", "user", "avatar"])

      defp avatar_file_url(file_name) do
        static_path = Path.join([avatar_static_dir(), file_name])
        Phoenix.VerifiedRoutes.static_url(MyAppWeb.Endpoint, "/" <> static_path)
      end

      defp avatar_file_name(entry) do
        [ext | _] = MIME.extensions(entry.client_type)
        "#{entry.uuid}.#{ext}"
      end

      # will be called in order to display files when editing item
      defp list_files_avatar(%{avatar: ""}), do: []
      defp list_files_avatar(%{avatar: avatar}), do: [avatar]

      # will be called to consume avatar
      # you may add completed file upload paths as part of the change in order to persist them
      # you have to return the (modified) change
      defp consume_avatar(socket, _resource, %{} = change) do
        consume_uploaded_entries(socket, :avatar, fn %{path: path}, entry ->
          file_name = avatar_file_name(entry)
          dest = Path.join([:code.priv_dir(:my_app), "static", avatar_static_dir(), file_name])
          File.cp!(path, dest)
          {:ok, avatar_file_url(file_name)}
        end)

        case uploaded_entries(socket, :avatar) do
          {[] = _completed, []} -> change
          {[entry | _] = _completed, []} -> Map.put(change, "avatar", avatar_file_name(entry))
        end
      end

      def remove_avatar(resource, _target) do
        Repo.get_by!(User, id: resource.id)
        |> User.changeset(%{avatar: ""})
        |> Repo.update!()

        []
      end

  ### Multiple Files

      @impl Backpex.LiveResource
      def fields do
      [
        gallery: %{
          module: Backpex.Fields.Upload,
          label: "Gallery",
          upload_key: :gallery,
          accept: ~w(.jpg .jpeg),
          max_entries: 5,
          list_files: &list_files_gallery/2,
          consume: &consume_gallery/3,
          remove: &remove_gallery/3,
        }
      ]
      end

      defp gallery_static_dir, do: Path.join(["uploads", "user", "gallery"])

      defp gallery_file_url(file_name) do
        static_path = Path.join([gallery_static_dir(), file_name])
        Phoenix.VerifiedRoutes.static_url(MyAppWeb.Endpoint, "/" <> static_path)
      end

      defp gallery_file_name(entry) do
        [ext | _] = MIME.extensions(entry.client_type)
        "#{entry.uuid}.#{ext}"
      end

      # will be called to consume uploads
      # you may add completed file upload paths as part of the change in order to persist them
      # you have to return the (modified) change
      def consume_gallery(socket, item, %{} = change) do
        consume_uploaded_entries(socket, :gallery, fn %{path: path}, entry ->
          file_name = gallery_file_name(entry)
          dest = Path.join([:code.priv_dir(:my_app), "static", gallery_static_dir(), file_name])
          File.cp!(path, dest)
          {:ok, gallery_file_url(file_name)}
        end)

        {completed, []} = uploaded_entries(socket, :gallery)

        file_names = Enum.map(completed, fn entry -> gallery_file_name(entry) end)

        file_names =
          case item do
            %{id: id} when is_binary(id) ->
              (Repo.get_by!(Event, id: id) |> Map.get(:gallery)) ++ file_names

            _ ->
              file_names
          end

        Map.put(change, "gallery", file_names)
      end

      # will be called in order to display files when editing item
      def list_files_gallery(%{gallery: gallery}), do: gallery

      # will be called when deleting certain file from existing item
      # target is the key you provided in list/2
      # remove files from file system and item, return new file paths to be displayed
      def remove_gallery(item, target) do
        element = Repo.get_by!(Event, id: item.id)

        file_paths =
          Map.get(element, :gallery)
          |> Enum.reject(&(&1 == target))

        Event.changeset(element, %{gallery: file_paths})
        |> Repo.update!()

        file_paths
      end
  """
  use BackpexWeb, :field

  import Phoenix.LiveView, only: [allow_upload: 3]

  @impl Backpex.Field
  def render_value(assigns) do
    %{field_options: field_options, item: item} = assigns

    uploaded_files = map_file_paths(field_options, item)

    assigns =
      assigns
      |> assign(:uploaded_files, uploaded_files)

    ~H"""
    <div class="flex flex-col">
      <p :for={{_file_key, label} <- @uploaded_files}>
        <%= label %>
      </p>
    </div>
    """
  end

  @impl Backpex.Field
  def render_form(assigns) do
    upload_key = assigns.field_options.upload_key
    uploads_allowed = not is_nil(assigns.field_uploads)

    assigns =
      assigns
      |> assign(:upload_key, upload_key)
      |> assign(:uploads_allowed, uploads_allowed)
      |> assign(:uploaded_files, Keyword.get(assigns.uploaded_files, upload_key))

    ~H"""
    <div>
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
            class="flex justify-center rounded-md border-2 border-dashed px-6 pt-5 pb-6"
            x-bind:class="dragging > 0 ? 'border-primary' : 'border-content'"
          >
            <div class="flex flex-col items-center space-y-1 text-center">
              <Heroicons.document_arrow_up class="h-8 w-8 text-gray-400" />
              <div class="flex text-sm">
                <label>
                  <a class="link link-hover link-primary font-medium">
                    <%= Backpex.translate("Upload a file") %>
                  </a>
                  <.live_file_input
                    :if={@uploads_allowed}
                    upload={@field_uploads}
                    phx-target="#form-component"
                    class="hidden"
                  />
                </label>
                <p class="pl-1"><%= Backpex.translate("or drag and drop") %></p>
              </div>
            </div>
          </div>
        </div>

        <section :if={(@uploads_allowed && Enum.count(@field_uploads.entries) > 0) || @uploaded_files > 0} class="mt-2">
          <article>
            <%= if @uploads_allowed do %>
              <div :for={entry <- @field_uploads.entries}>
                <div class="flex space-x-2">
                  <p><%= Map.get(entry, :client_name) %></p>

                  <button
                    type="button"
                    phx-click="cancel-entry"
                    phx-value-ref={entry.ref}
                    phx-value-id={@upload_key}
                    phx-target="#form-component"
                  >
                    &times;
                  </button>
                </div>

                <p :for={err <- upload_errors(@field_uploads, entry)} class="text-xs italic text-red-500">
                  <%= error_to_string(err) %>
                </p>
              </div>
            <% end %>

            <%= if @type == :form do %>
              <div :for={{file_key, label} <- @uploaded_files}>
                <p class="inline"><%= label %></p>

                <button
                  type="button"
                  phx-click="cancel-existing-entry"
                  phx-value-ref={file_key}
                  phx-value-id={@upload_key}
                  phx-target="#form-component"
                >
                  &times;
                </button>
              </div>
            <% end %>
          </article>

          <%= if @uploads_allowed do %>
            <p :for={err <- upload_errors(@field_uploads)} class="text-xs italic text-red-500">
              <%= error_to_string(err) %>
            </p>
          <% end %>
        </section>
      </Layout.field_container>
    </div>
    """
  end

  @impl Backpex.Field
  def assign_uploads({_name, field_options}, socket) do
    field_files = {field_options.upload_key, map_file_paths(field_options, socket.assigns.item)}
    max_entries = field_options.max_entries - (field_files |> elem(1) |> Enum.count())
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

    socket
    |> assign(:uploaded_files, [field_files | uploaded_files])
  end

  defp allow_field_uploads(socket, _field_options, 0, _max_file_size), do: socket

  defp allow_field_uploads(socket, field_options, max_entries, max_file_size) do
    allow_upload(socket, field_options.upload_key,
      accept: field_options.accept,
      max_entries: max_entries,
      max_file_size: max_file_size
    )
  end

  @doc """
  Maps uploaded files to keyword list with identifier and label.

    ## Examples
      iex> Backpex.Fields.Upload.map_file_paths(%{list_files: fn item -> item.file_paths end}, %{file_paths: ["xyz.png"]})
      [{"xyz.png", "xyz.png"}]
  """
  def map_file_paths(field_options, file_paths) when is_list(file_paths) do
    file_paths
    |> Enum.map(&{&1, label_from_file(field_options, &1)})
  end

  def map_file_paths(%{list_files: list_files} = field_options, item) do
    item
    |> list_files.()
    |> Enum.map(&{&1, label_from_file(field_options, &1)})
  end

  def map_file_paths(field_options, item) do
    item
    |> Map.get(:file_paths, nil)
    |> Enum.map(&label_from_file(field_options, &1))
  end

  defp error_to_string(:too_large), do: Backpex.translate("too large")
  defp error_to_string(:too_many_files), do: Backpex.translate("too many files")
  defp error_to_string(:not_accepted), do: Backpex.translate("unacceptable file type")

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
end
