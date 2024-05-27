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
      |> update_assigns()
      |> assign_form()

    {:ok, socket}
  end

  defp update_assigns(%{assigns: %{action_type: :item}} = socket) do
    socket
    |> assign_new(:show_form_errors, fn -> false end)
    |> assign_fields()
    |> assign_changeset()
  end

  defp update_assigns(%{assigns: assigns} = socket) do
    socket
    |> assign(:show_form_errors, assigns.live_action == :edit)
    |> apply_action(assigns.live_action)
    |> maybe_assign_uploads()
  end

  defp maybe_assign_uploads(socket) do
    Enum.reduce(socket.assigns.fields, socket, fn {_name, field_options} = field, acc ->
      field_options.module.assign_uploads(field, acc)
    end)
  end

  defp assign_fields(%{assigns: %{action_to_confirm: action_to_confirm}} = socket) do
    socket
    |> assign_new(:fields, fn -> action_to_confirm.module.fields() end)
    |> assign(:save_label, action_to_confirm.module.confirm_label(socket.assigns))
  end

  defp assign_changeset(%{assigns: %{action_to_confirm: action_to_confirm}} = socket) do
    init_change = action_to_confirm.module.init_change(socket.assigns)
    changeset_function = &action_to_confirm.module.changeset/3

    socket
    |> assign(item_action_types: init_change)
    |> assign(:changeset_function, changeset_function)
    |> assign_new(:changeset, fn ->
      init_change
      |> Ecto.Changeset.change()
      |> LiveResource.call_changeset_function(changeset_function, %{}, socket.assigns)
    end)
  end

  defp apply_action(socket, action) when action in [:edit, :new] do
    socket
    |> assign(:save_label, Backpex.translate("Save"))
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
      assigns: %{item_action_types: item_action_types, changeset_function: changeset_function, fields: fields} = assigns
    } = socket

    target = Enum.at(target, 1)

    change =
      change
      |> drop_readonly_changes(fields, assigns)
      |> put_upload_change(socket, :validate)

    changeset = Resource.change(item_action_types, change, changeset_function, assigns, [], target)
    form = Phoenix.Component.to_form(changeset, as: :change)

    send(self(), {:update_changeset, changeset})

    socket = assign(socket, :form, form)

    {:noreply, socket}
  end

  def handle_event("validate", %{"change" => change, "_target" => target}, socket) do
    %{assigns: %{item: item, changeset_function: changeset_function, fields: fields} = assigns} = socket

    target = Enum.at(target, 1)
    assocs = Map.get(assigns, :assocs, [])

    change =
      change
      |> drop_readonly_changes(fields, assigns)
      |> put_upload_change(socket, :validate)

    changeset = Resource.change(item, change, changeset_function, assigns, assocs, target)
    form = Phoenix.Component.to_form(changeset, as: :change)

    send(self(), {:update_changeset, changeset})

    socket = assign(socket, :form, form)

    {:noreply, socket}
  end

  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("cancel-entry", %{"ref" => ref, "id" => id}, socket) do
    socket = cancel_upload(socket, String.to_existing_atom(id), ref)

    {:noreply, socket}
  end

  def handle_event("cancel-existing-entry", %{"ref" => file_key, "id" => upload_key}, socket) do
    upload_key = String.to_existing_atom(upload_key)

    {_field_name, field_options} =
      socket.assigns.fields()
      |> Enum.find(fn {_name, field_options} ->
        Map.has_key?(field_options, :upload_key) and Map.get(field_options, :upload_key) == upload_key
      end)

    item = Map.get(socket.assigns, :item)
    file_paths = Upload.map_file_paths(field_options, field_options.remove.(item, file_key))
    uploaded_files = Keyword.put(socket.assigns[:uploaded_files], upload_key, file_paths)

    socket =
      socket
      |> assign(:uploaded_files, uploaded_files)
      |> update_max_entries(field_options, field_options.max_entries - Enum.count(file_paths))

    {:noreply, socket}
  end

  def handle_event("save", %{"action-key" => key, "change" => change}, %{assigns: %{action_type: :item}} = socket) do
    key = String.to_existing_atom(key)
    handle_item_action(socket, key, change)
  end

  def handle_event("save", %{"change" => change}, socket) do
    %{assigns: %{live_action: live_action, fields: fields} = assigns} = socket

    change =
      change
      |> put_upload_change(socket, :insert)
      |> drop_readonly_changes(fields, assigns)

    handle_save(socket, live_action, change)
  end

  def handle_event("save", %{"action-key" => key}, socket) do
    key = String.to_existing_atom(key)
    handle_item_action(socket, key, %{})
  end

  def handle_event("save", _params, socket) do
    handle_item_action(socket, nil, %{})
  end

  def handle_event(msg, params, socket) do
    socket =
      Enum.reduce(socket.assigns.fields, socket, fn el, acc ->
        el.module.handle_form_event(el, msg, params, acc)
      end)

    {:noreply, socket}
  end

  defp handle_save(socket, :new, params) do
    %{
      assigns:
        %{
          repo: repo,
          live_resource: live_resource,
          singular_name: singular_name,
          changeset_function: changeset_function,
          item: item
        } = assigns
    } = socket

    opts = [
      assigns: assigns,
      pubsub: assigns[:pubsub],
      assocs: Map.get(assigns, :assocs, []),
      after_save: fn item ->
        consume_uploads(socket)
        live_resource.on_item_created(socket, item)

        {:ok, item}
      end
    ]

    case Resource.insert(item, params, repo, changeset_function, opts) do
      {:ok, item} ->
        return_to = live_resource.return_to(socket, assigns, :new, item)
        info_msg = Backpex.translate({"New %{resource} has been created successfully.", %{resource: singular_name}})

        socket =
          socket
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

  defp handle_save(socket, :edit, params) do
    %{
      assigns:
        %{
          repo: repo,
          live_resource: live_resource,
          singular_name: singular_name,
          changeset_function: changeset_function,
          item: item
        } = assigns
    } = socket

    opts = [
      assigns: assigns,
      pubsub: assigns[:pubsub],
      assocs: Map.get(assigns, :assocs, []),
      after_save: fn item ->
        consume_uploads(socket)
        live_resource.on_item_updated(socket, item)

        {:ok, item}
      end
    ]

    case Resource.update(item, params, repo, changeset_function, opts) do
      {:ok, item} ->
        return_to = live_resource.return_to(socket, assigns, :edit, item)
        info_msg = Backpex.translate({"%{resource} has been edited successfully.", %{resource: singular_name}})

        socket =
          socket
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

  defp handle_save(socket, :resource_action, params) do
    %{
      assigns:
        %{
          resource_action: resource_action,
          item: item,
          changeset_function: changeset_function,
          return_to: return_to
        } = assigns
    } = socket

    assocs = Map.get(assigns, :assocs, [])
    changeset = Backpex.Resource.change(item, params, changeset_function, assigns, assocs)

    case changeset do
      %{valid?: true} ->
        result = resource_action.module.handle(socket, params)

        if match?({:ok, _msg}, result), do: consume_uploads(socket)

        socket =
          socket
          |> put_flash_message(result)
          |> push_redirect(to: return_to)

        {:noreply, socket}

      _not_valid ->
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
          changeset_function: changeset_function
        } = assigns
    } = socket

    changeset = Backpex.Resource.change(item_action_types, params, changeset_function, assigns)

    case changeset do
      %{valid?: true} ->
        selected_items =
          Enum.filter(selected_items, fn item ->
            LiveResource.can?(socket.assigns, action_key, item, socket.assigns.live_resource)
          end)

        {message, socket} =
          socket
          |> assign(selected_items: [])
          |> assign(select_all: false)
          |> action_to_confirm.module.handle(selected_items, params)

        {message, push_patch(socket, to: return_to)}

      _not_valid ->
        form = Phoenix.Component.to_form(changeset, as: :change)

        socket =
          socket
          |> assign(:show_form_errors, true)
          |> assign(:form, form)

        {:noreply, socket}
    end
  end

  defp update_max_entries(socket, %{upload_key: key} = field_options, count) do
    upload_config = Map.get(socket.assigns, :uploads, %{})
    upload_entry = Map.get(upload_config, key)

    if is_nil(upload_entry) do
      socket
      |> allow_upload(key, accept: field_options.accept, max_entries: count)
    else
      socket
      |> assign(:uploads, Map.put(upload_config, key, Map.merge(upload_entry, %{max_entries: count})))
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

  defp put_upload_change(change, socket, action) do
    Enum.reduce(socket.assigns.fields, change, fn
      {_name, %{upload_key: upload_key} = field_options} = _field, acc ->
        %{put_upload_change: put_upload_change} = field_options

        uploaded_entries = uploaded_entries(socket, upload_key)
        put_upload_change.(socket, acc, uploaded_entries, action)

      _field, acc ->
        acc
    end)
  end

  defp consume_uploads(%{assigns: %{uploads: _uploads}} = socket) do
    for {_name, %{upload_key: upload_key} = field_options} = _field <- socket.assigns.fields do
      if Map.has_key?(socket.assigns.uploads, upload_key) do
        %{consume_upload: consume_upload} = field_options

        consume_uploaded_entries(socket, upload_key, fn meta, entry ->
          consume_upload.(socket, meta, entry)
        end)
      end
    end
  end

  defp consume_uploads(_socket), do: :ok

  def render(assigns) do
    form_component(assigns)
  end
end
