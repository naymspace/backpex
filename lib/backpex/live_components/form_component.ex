defmodule Backpex.FormComponent do
  @moduledoc """
  The form live component.
  """

  use BackpexWeb, :html
  use Phoenix.LiveComponent

  import Backpex.HTML.Resource

  alias Backpex.Fields.Upload
  alias Backpex.LiveResource
  alias Backpex.Resource
  alias Backpex.ResourceAction

  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:action_type, fn -> nil end)
      |> assign_new(:continue_label, fn -> nil end)
      |> assign_new(:show_form_errors, fn -> false end)
      |> update_assigns()
      |> assign_form()

    {:ok, socket}
  end

  defp update_assigns(%{assigns: %{action_type: :item}} = socket) do
    socket
    |> assign_fields()
  end

  defp update_assigns(%{assigns: assigns} = socket) do
    socket
    |> apply_action(assigns.live_action)
    |> maybe_assign_uploads()
  end

  defp maybe_assign_uploads(socket) do
    socket =
      Enum.reduce(socket.assigns.fields, socket, fn {_name, field_options} = field, acc ->
        field_options.module.assign_uploads(field, acc)
      end)

    assign_new(socket, :removed_uploads, fn -> Keyword.new() end)
  end

  defp assign_fields(%{assigns: %{action_to_confirm: action_to_confirm}} = socket) do
    socket
    |> assign_new(:fields, fn -> action_to_confirm.module.fields() end)
    |> assign(:save_label, action_to_confirm.module.confirm_label(socket.assigns))
  end

  defp apply_action(socket, action) when action in [:edit, :new] do
    socket
    |> assign(:save_label, Backpex.translate("Save"))
    |> assign(:continue_label, Backpex.translate("Save & Continue editing"))
  end

  defp apply_action(socket, :resource_action) do
    %{assigns: %{resource_action: resource_action}} = socket

    socket
    |> assign(:save_label, ResourceAction.name(resource_action, :label))
    |> assign(:fields, resource_action.module.fields())
  end

  defp assign_form(socket) do
    changeset = socket.assigns.changeset
    form = Phoenix.Component.to_form(changeset, as: :change)

    assign(socket, :form, form)
  end

  def handle_event("validate", %{"change" => change, "_target" => target}, %{assigns: %{action_type: :item}} = socket) do
    %{
      assigns:
        %{
          item_action_types: item_action_types,
          changeset_function: changeset_function,
          repo: repo,
          fields: fields
        } = assigns
    } = socket

    target = Enum.at(target, 1)

    change =
      change
      |> drop_readonly_changes(fields, assigns)
      |> put_upload_change(socket, :validate)

    changeset =
      item_action_types
      |> Resource.change(change, changeset_function, repo, fields, assigns, target: target)

    form = Phoenix.Component.to_form(changeset, as: :change)

    send(self(), {:update_changeset, changeset})

    socket =
      socket
      |> assign(:form, form)
      |> assign(:show_form_errors, false)

    {:noreply, socket}
  end

  def handle_event("validate", %{"change" => change, "_target" => target}, socket) do
    %{assigns: %{item: item, changeset_function: changeset_function, repo: repo, fields: fields} = assigns} = socket

    target = Enum.at(target, 1)
    assocs = Map.get(assigns, :assocs, [])

    change =
      change
      |> drop_readonly_changes(fields, assigns)
      |> put_upload_change(socket, :validate)

    changeset =
      item
      |> Resource.change(change, changeset_function, repo, fields, assigns, assocs: assocs, target: target)

    form = Phoenix.Component.to_form(changeset, as: :change)

    send(self(), {:update_changeset, changeset})

    socket =
      socket
      |> assign(:form, form)
      |> assign(:show_form_errors, false)

    {:noreply, socket}
  end

  def handle_event("validate", _params, socket) do
    socket = assign(socket, :show_form_errors, false)

    {:noreply, socket}
  end

  def handle_event("cancel-entry", %{"ref" => ref, "id" => id}, socket) do
    socket = cancel_upload(socket, String.to_existing_atom(id), ref)

    {:noreply, socket}
  end

  def handle_event("cancel-existing-entry", %{"ref" => file_key, "id" => upload_key}, socket) do
    upload_key = String.to_existing_atom(upload_key)

    field =
      socket.assigns.fields()
      |> Enum.find(fn {_name, field_options} ->
        Map.has_key?(field_options, :upload_key) and Map.get(field_options, :upload_key) == upload_key
      end)

    removed_uploads =
      socket.assigns
      |> Map.get(:removed_uploads, [])
      |> Keyword.update(upload_key, [file_key], fn existing -> [file_key | existing] end)

    files = Upload.existing_file_paths(field, socket.assigns.item, Keyword.get(removed_uploads, upload_key, []))
    uploaded_files = Keyword.put(socket.assigns[:uploaded_files], upload_key, files)

    socket =
      socket
      |> assign(:removed_uploads, removed_uploads)
      |> assign(:uploaded_files, uploaded_files)

    {:noreply, socket}
  end

  def handle_event("save", %{"action-key" => key, "change" => change}, %{assigns: %{action_type: :item}} = socket) do
    key = String.to_existing_atom(key)
    handle_item_action(socket, key, change)
  end

  def handle_event("save", %{"change" => change, "save-type" => save_type}, socket) do
    %{assigns: %{live_action: live_action, fields: fields} = assigns} = socket

    change =
      change
      |> put_upload_change(socket, :insert)
      |> drop_readonly_changes(fields, assigns)

    handle_save(socket, live_action, change, save_type)
  end

  def handle_event("save", %{"action-key" => key}, socket) do
    key = String.to_existing_atom(key)
    handle_item_action(socket, key, %{})
  end

  def handle_event("save", _params, socket) do
    change = put_upload_change(%{}, socket, :insert)

    handle_save(socket, socket.assigns.live_action, change)
  end

  def handle_event(msg, params, socket) do
    socket =
      Enum.reduce(socket.assigns.fields, socket, fn el, acc ->
        el.module.handle_form_event(el, msg, params, acc)
      end)

    {:noreply, socket}
  end

  defp handle_save(socket, key, params, save_type \\ "save")

  defp handle_save(socket, :new, params, save_type) do
    %{
      assigns:
        %{
          repo: repo,
          live_resource: live_resource,
          changeset_function: changeset_function,
          fields: fields,
          item: item
        } = assigns
    } = socket

    opts = [
      assigns: assigns,
      pubsub: assigns[:pubsub],
      assocs: Map.get(assigns, :assocs, []),
      after_save: fn item ->
        handle_uploads(socket, item)
        live_resource.on_item_created(socket, item)

        {:ok, item}
      end
    ]

    case Resource.insert(item, params, repo, fields, changeset_function, opts) do
      {:ok, item} ->
        return_to = return_to_path(save_type, live_resource, socket, assigns, item, :new)

        socket =
          socket
          |> assign(:show_form_errors, false)
          |> clear_flash()
          |> put_flash(:info, assigns.resource_created_message)
          |> push_navigate(to: return_to)

        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        form = Phoenix.Component.to_form(changeset, as: :change)

        socket =
          socket
          |> assign(:show_form_errors, true)
          |> assign(:form, form)

        send(self(), {:update_changeset, changeset})

        {:noreply, socket}
    end
  end

  defp handle_save(socket, :edit, params, save_type) do
    %{
      assigns:
        %{
          repo: repo,
          live_resource: live_resource,
          singular_name: singular_name,
          changeset_function: changeset_function,
          item: item,
          fields: fields
        } = assigns
    } = socket

    opts = [
      assigns: assigns,
      pubsub: assigns[:pubsub],
      assocs: Map.get(assigns, :assocs, []),
      after_save: fn item ->
        handle_uploads(socket, item)
        live_resource.on_item_updated(socket, item)

        {:ok, item}
      end
    ]

    case Resource.update(item, params, repo, fields, changeset_function, opts) do
      {:ok, item} ->
        return_to = return_to_path(save_type, live_resource, socket, assigns, item, :edit)
        info_msg = Backpex.translate({"%{resource} has been edited successfully.", %{resource: singular_name}})

        socket =
          socket
          |> assign(:show_form_errors, false)
          |> clear_flash()
          |> put_flash(:info, info_msg)
          |> push_navigate(to: return_to)

        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        form = Phoenix.Component.to_form(changeset, as: :change)

        socket =
          socket
          |> assign(:show_form_errors, true)
          |> assign(:form, form)

        send(self(), {:update_changeset, changeset})

        {:noreply, socket}
    end
  end

  defp handle_save(socket, :resource_action, params, _save_type) do
    %{
      assigns:
        %{
          resource_action: resource_action,
          item: item,
          changeset_function: changeset_function,
          return_to: return_to,
          repo: repo,
          fields: fields
        } = assigns
    } = socket

    assocs = Map.get(assigns, :assocs, [])

    result =
      item
      |> Resource.change(params, changeset_function, repo, fields, assigns, assocs: assocs)
      |> Ecto.Changeset.apply_action(:insert)

    case result do
      {:ok, data} ->
        resource_action_result = resource_action.module.handle(socket, data)

        if match?({:ok, _msg}, resource_action_result), do: handle_uploads(socket, data)

        socket =
          socket
          |> assign(:show_form_errors, false)
          |> put_flash_message(resource_action_result)
          |> push_navigate(to: return_to)

        {:noreply, socket}

      {:error, changeset} ->
        form = Phoenix.Component.to_form(changeset, as: :change)

        socket =
          socket
          |> assign(:show_form_errors, true)
          |> assign(:form, form)

        send(self(), {:update_changeset, changeset})

        {:noreply, socket}
    end
  end

  defp handle_item_action(socket, action_key, params) do
    %{
      assigns:
        %{
          selected_items: selected_items,
          action_to_confirm: action_to_confirm,
          return_to: return_to,
          item_action_types: item_action_types,
          changeset_function: changeset_function,
          repo: repo,
          fields: fields
        } = assigns
    } = socket

    result =
      item_action_types
      |> Backpex.Resource.change(params, changeset_function, repo, fields, assigns)
      |> Ecto.Changeset.apply_action(:insert)

    case result do
      {:ok, data} ->
        selected_items =
          Enum.filter(selected_items, fn item ->
            LiveResource.can?(socket.assigns, action_key, item, socket.assigns.live_resource)
          end)

        {message, socket} =
          socket
          |> assign(:show_form_errors, false)
          |> assign(selected_items: [])
          |> assign(select_all: false)
          |> action_to_confirm.module.handle(selected_items, data)

        {message, push_patch(socket, to: return_to)}

      {:error, changeset} ->
        form = Phoenix.Component.to_form(changeset, as: :change)

        socket =
          socket
          |> assign(:show_form_errors, true)
          |> assign(:form, form)

        {:noreply, socket}
    end
  end

  defp drop_readonly_changes(change, fields, assigns) do
    read_only =
      fields
      |> Enum.filter(&Backpex.Field.readonly?(&1, assigns))
      |> Enum.map(&Atom.to_string(&1.name))

    Map.drop(change, read_only)
  end

  defp put_flash_message(socket, {type, msg}) do
    socket
    |> clear_flash()
    |> put_flash(flash_key(type), msg)
  end

  defp flash_key(:ok), do: :info
  defp flash_key(:error), do: :error

  defp return_to_path("continue", _live_resource, _socket, %{current_url: url}, item, :new) do
    url
    |> URI.parse()
    |> Map.get(:path)
    |> Path.dirname()
    |> Kernel.<>("/#{item.id}/edit")
  end

  defp return_to_path("continue", _live_resource, _socket, %{current_url: url}, _item, :edit) do
    URI.parse(url).path
  end

  defp return_to_path(_save_type, live_resource, socket, assigns, item, type) do
    live_resource.return_to(socket, assigns, type, item)
  end

  defp put_upload_change(change, socket, action) do
    Enum.reduce(socket.assigns.fields, change, fn
      {_name, %{upload_key: upload_key} = field_options} = _field, acc ->
        %{put_upload_change: put_upload_change} = field_options

        uploaded_entries = uploaded_entries(socket, upload_key)
        removed_entries = Keyword.get(socket.assigns.removed_uploads, upload_key, [])

        put_upload_change.(socket, acc, socket.assigns.item, uploaded_entries, removed_entries, action)

      _field, acc ->
        acc
    end)
  end

  defp handle_uploads(%{assigns: %{uploads: _uploads}} = socket, item) do
    for {_name, %{upload_key: upload_key} = field_options} = _field <- socket.assigns.fields do
      if Map.has_key?(socket.assigns.uploads, upload_key) do
        %{consume_upload: consume_upload, remove_uploads: remove_uploads} = field_options

        consume_uploaded_entries(socket, upload_key, fn meta, entry ->
          consume_upload.(socket, item, meta, entry)
        end)

        removed_entries = Keyword.get(socket.assigns.removed_uploads, upload_key, [])
        remove_uploads.(socket, item, removed_entries)
      end
    end
  end

  defp handle_uploads(_socket, _item), do: :ok

  def render(assigns) do
    form_component(assigns)
  end
end
