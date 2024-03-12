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

  def handle_event(
        "validate",
        %{"change" => change, "_target" => target},
        %{assigns: %{action_type: :item} = assigns} = socket
      ) do
    target = Enum.at(target, 1)

    changeset =
      Ecto.Changeset.change(assigns.item_action_types)
      |> validate_change(assigns.changeset_function, change, assigns, target)

    socket = assign(socket, changeset: changeset)

    {:noreply, socket}
  end

  def handle_event("validate", %{"change" => change, "_target" => target}, socket) do
    %{assigns: %{item: item, changeset_function: changeset_function} = assigns} = socket

    target = Enum.at(target, 1)
    assocs = Map.get(assigns, :assocs, [])

    changeset =
      Ecto.Changeset.change(item)
      |> put_assocs(assocs)
      |> validate_change(changeset_function, change, assigns, target)

    send(self(), {:update_changeset, changeset})

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

  def handle_event(
        "save",
        %{"action-key" => key, "change" => change},
        %{assigns: %{action_type: :item} = assigns} = socket
      ) do
    key = String.to_existing_atom(key)

    changeset =
      Ecto.Changeset.change(assigns.item_action_types)
      |> validate_change(assigns.changeset_function, change, assigns, nil)

    socket = assign(socket, changeset: changeset)

    case changeset do
      %{valid?: true} -> save_items(socket, assigns, key, change)
      _changeset -> {:noreply, assign(socket, show_form_errors: true)}
    end
  end

  def handle_event("save", %{"change" => change}, socket) do
    %{assigns: %{item: item, changeset_function: changeset_function} = assigns} = socket

    assocs = Map.get(assigns, :assocs, [])

    changeset =
      Ecto.Changeset.change(item)
      |> put_assocs(assocs)
      |> validate_change(changeset_function, change, assigns, nil)

    socket = assign(socket, changeset: changeset)

    send(self(), {:update_changeset, changeset})

    case changeset do
      %{valid?: true} -> save_items(socket, assigns, change)
      _changeset -> {:noreply, assign(socket, show_form_errors: true)}
    end
  end

  def handle_event("save", %{"action-key" => key}, socket) do
    key = String.to_existing_atom(key)

    save_items(socket, socket.assigns, key, %{})
  end

  def handle_event("save", _params, socket) do
    save_items(socket, socket.assigns, nil, %{})
  end

  def handle_event(msg, params, socket) do
    socket =
      Enum.reduce(socket.assigns.fields, socket, fn el, acc ->
        el.module.handle_form_event(el, msg, params, acc)
      end)

    {:noreply, socket}
  end

  defp validate_change(item, changeset_function, change, assigns, target) do
    item
    |> LiveResource.call_changeset_function(changeset_function, change, assigns, target)
    |> Map.put(:action, :validate)
  end

  defp put_assocs(changeset, assocs) do
    Enum.reduce(assocs, changeset, fn {key, value}, acc ->
      Ecto.Changeset.put_assoc(acc, key, value)
    end)
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

  defp save_items(socket, %{selected_items: selected_items}, key, change) do
    selected_items =
      Enum.filter(selected_items, fn item ->
        LiveResource.can?(socket.assigns, key, item, socket.assigns.live_resource)
      end)

    save_items(socket, selected_items, change)
  end

  defp save_items(socket, %{live_action: :new}, change) do
    %{
      assigns:
        %{
          live_resource: live_resource,
          fields: fields
        } = assigns
    } = socket

    unless LiveResource.can?(socket.assigns, :new, nil, live_resource),
      do: raise(Backpex.ForbiddenError)

    change =
      change
      |> drop_readonly_changes(fields, assigns)
      |> handle_upload(socket)

    result = Resource.insert(socket.assigns, change)

    case result do
      {:ok, item} ->
        socket =
          socket
          |> clear_flash()
          |> put_flash(
            :info,
            Backpex.translate(
              {"New %{resource} has been created successfully.", %{resource: socket.assigns.singular_name}}
            )
          )
          |> push_navigate(to: live_resource.return_to(socket, socket.assigns, :new, item))
          |> live_resource.on_item_created(item)

        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        new_socket =
          socket
          |> assign(:show_form_errors, true)

        send(self(), {:update_changeset, changeset})

        {:noreply, new_socket}
    end
  end

  defp save_items(socket, %{live_action: :edit}, change) do
    %{
      assigns:
        %{
          item: item,
          live_resource: live_resource,
          singular_name: singular_name,
          fields: fields
        } = assigns
    } = socket

    unless LiveResource.can?(assigns, :edit, item, live_resource), do: raise(Backpex.ForbiddenError)

    change =
      change
      |> drop_readonly_changes(fields, assigns)
      |> handle_upload(socket)

    case Resource.update(assigns, change) do
      {:ok, item} ->
        socket =
          socket
          |> clear_flash()
          |> put_flash(
            :info,
            Backpex.translate({"%{resource} has been edited successfully.", %{resource: singular_name}})
          )
          |> push_navigate(to: live_resource.return_to(socket, assigns, :edit, item))
          |> live_resource.on_item_updated(item)

        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        send(self(), {:update_changeset, changeset})

        {:noreply, socket}
    end
  end

  defp save_items(socket, %{live_action: :resource_action}, change) do
    %{assigns: %{fields: fields, resource_action: resource_action, return_to: return_to} = assigns} = socket

    change = drop_readonly_changes(change, fields, assigns)
    result = resource_action.module.handle(socket, handle_upload(change, socket))

    socket =
      socket
      |> put_flash_message(result)
      |> push_redirect(to: return_to)

    {:noreply, socket}
  end

  defp save_items(socket, selected_items, change) do
    %{assigns: %{fields: fields, action_to_confirm: action_to_confirm, return_to: return_to} = assigns} = socket
    change = drop_readonly_changes(change, fields, assigns)

    {message, socket} =
      socket
      |> assign(selected_items: [])
      |> assign(select_all: false)
      |> action_to_confirm.module.handle(selected_items, change)

    {message, push_patch(socket, to: return_to)}
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

  defp handle_upload(change, %{assigns: %{uploads: _uploads}} = socket) do
    Enum.reduce(socket.assigns.fields, change, fn
      {_name, %{upload_key: upload_key} = field_options} = _field, acc ->
        if Map.has_key?(socket.assigns.uploads, upload_key) do
          field_options.consume.(socket, socket.assigns.item, acc)
        else
          acc
        end

      _field, acc ->
        acc
    end)
  end

  defp handle_upload(change, _socket), do: change

  def render(assigns) do
    form_component(assigns)
  end
end
