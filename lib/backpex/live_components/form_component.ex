defmodule Backpex.FormComponent do
  @moduledoc """
  The form live component.
  """
  use BackpexWeb, :html
  use Phoenix.LiveComponent
  alias Backpex.Fields.Upload
  alias Backpex.Resource
  alias Backpex.ResourceAction

  def update(assigns, socket) do
    socket
    |> assign(assigns)
    |> assign_new(:action_type, fn -> nil end)
    |> assign_new(:continue_label, fn -> nil end)
    |> assign_new(:show_form_errors, fn -> false end)
    |> update_assigns()
    |> assign_form()
    |> ok()
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
    |> assign(:save_label, Backpex.translate(socket.assigns.live_resource, {"Save", %{}}, :general))
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
    %{assigns: %{item: item, fields: fields} = assigns} = socket

    changeset_function = &assigns.action_to_confirm.module.changeset/3

    target = Enum.at(target, 1)

    change =
      change
      |> drop_readonly_changes(fields, assigns)
      |> put_upload_change(socket, :validate)

    metadata = Resource.build_changeset_metadata(socket.assigns, target)

    changeset =
      item
      |> changeset_function.(change, metadata)
      |> Map.put(:action, :validate)

    form = Phoenix.Component.to_form(changeset, as: :change)

    send(self(), {:update_changeset, changeset})

    socket
    |> assign(:form, form)
    |> assign(:show_form_errors, false)
    |> noreply()
  end

  def handle_event("validate", %{"change" => change, "_target" => target}, socket) do
    %{
      live_resource: live_resource,
      item: item,
      fields: fields
    } = socket.assigns

    target = Enum.at(target, 1)
    assocs = Map.get(socket.assigns, :assocs, [])

    change =
      change
      |> drop_readonly_changes(fields, socket.assigns)
      |> put_upload_change(socket, :validate)

    opts = [target: target, assocs: assocs]
    changeset = Resource.change(item, change, fields, socket.assigns, live_resource, opts)

    form = Phoenix.Component.to_form(changeset, as: :change)

    send(self(), {:update_changeset, changeset})

    socket
    |> assign(:form, form)
    |> assign(:show_form_errors, false)
    |> noreply()
  end

  def handle_event("validate", _params, socket) do
    socket
    |> assign(:show_form_errors, false)
    |> noreply()
  end

  def handle_event("cancel-entry", %{"ref" => ref, "id" => upload_key}, socket) do
    socket
    |> cancel_upload(String.to_existing_atom(upload_key), ref)
    |> push_event("cancel-entry:#{upload_key}", %{})
    |> noreply()
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

    socket
    |> assign(:removed_uploads, removed_uploads)
    |> assign(:uploaded_files, uploaded_files)
    |> push_event("cancel-existing-entry:#{upload_key}", %{})
    |> noreply()
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
      |> drop_unused_changes()

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
    Enum.reduce(socket.assigns.fields, socket, fn el, acc ->
      el.module.handle_form_event(el, msg, params, acc)
    end)
    |> noreply()
  end

  defp handle_save(socket, key, params, save_type \\ "save")

  defp handle_save(socket, :new, params, save_type) do
    %{assigns: %{live_resource: live_resource, item: item} = assigns} = socket

    opts = [
      assocs: Map.get(assigns, :assocs, []),
      after_save_fun: fn item ->
        handle_uploads(socket, item)
        live_resource.on_item_created(socket, item)

        {:ok, item}
      end
    ]

    case Resource.insert(item, params, socket.assigns, live_resource, opts) do
      {:ok, item} ->
        return_to = return_to_path(save_type, live_resource, socket, socket.assigns, item, :new)

        socket
        |> assign(:show_form_errors, false)
        |> clear_flash()
        |> put_flash(
          :info,
          Backpex.translate(
            live_resource,
            {"New %{resource} has been created successfully.", %{resource: live_resource.singular_name()}}
          )
        )
        |> push_navigate(to: return_to)
        |> noreply()

      {:error, %Ecto.Changeset{} = changeset} ->
        form = Phoenix.Component.to_form(changeset, as: :change)

        send(self(), {:update_changeset, changeset})

        socket
        |> assign(:show_form_errors, true)
        |> assign(:form, form)
        |> noreply()
    end
  end

  defp handle_save(socket, :edit, params, save_type) do
    %{live_resource: live_resource, singular_name: singular_name, item: item, fields: fields} = socket.assigns

    opts = [
      assocs: Map.get(socket.assigns, :assocs, []),
      after_save_fun: fn item ->
        handle_uploads(socket, item)
        live_resource.on_item_updated(socket, item)

        {:ok, item}
      end
    ]

    case Resource.update(item, params, fields, socket.assigns, live_resource, opts) do
      {:ok, item} ->
        return_to = return_to_path(save_type, live_resource, socket, socket.assigns, item, :edit)
        info_msg = Backpex.translate({"%{resource} has been edited successfully.", %{resource: singular_name}})

        socket
        |> assign(:show_form_errors, false)
        |> clear_flash()
        |> put_flash(:info, info_msg)
        |> push_navigate(to: return_to)
        |> noreply()

      {:error, %Ecto.Changeset{} = changeset} ->
        form = Phoenix.Component.to_form(changeset, as: :change)

        send(self(), {:update_changeset, changeset})

        socket
        |> assign(:show_form_errors, true)
        |> assign(:form, form)
        |> noreply()
    end
  end

  defp handle_save(socket, :resource_action, params, _save_type) do
    %{
      assigns:
        %{
          live_resource: live_resource,
          resource_action: resource_action,
          item: item,
          return_to: return_to,
          fields: fields
        } = assigns
    } = socket

    assocs = Map.get(assigns, :assocs, [])
    params = drop_readonly_changes(params, fields, assigns)

    result =
      item
      |> Resource.change(params, fields, assigns, live_resource, assocs: assocs)
      |> Ecto.Changeset.apply_action(:insert)

    with {:ok, data} <- result,
         {:ok, socket} <- resource_action.module.handle(socket, data) do
      handle_uploads(socket, data)

      socket
      |> assign(:show_form_errors, false)
      |> push_navigate(to: return_to)
      |> noreply()
    else
      {:error, changeset} ->
        form = Phoenix.Component.to_form(changeset, as: :change)

        send(self(), {:update_changeset, changeset})

        socket
        |> assign(:show_form_errors, true)
        |> assign(:form, form)
        |> noreply()

      unexpected_return ->
        raise ArgumentError, """
        Invalid return value from #{inspect(resource_action.module)}.handle/2.

        Expected: {:ok, socket} or {:error, changeset}
        Got: #{inspect(unexpected_return)}

        Resource Actions must return {:ok, socket} or {:error, changeset}.
        """
    end
  end

  defp handle_item_action(socket, action_key, params) do
    %{
      assigns:
        %{
          live_resource: live_resource,
          selected_items: selected_items,
          action_to_confirm: action_to_confirm,
          fields: fields,
          return_to: return_to
        } = assigns
    } = socket

    params = drop_readonly_changes(params, fields, assigns)

    result =
      if Backpex.ItemAction.has_form?(action_to_confirm) do
        changeset_function = &action_to_confirm.module.changeset/3

        metadata = Resource.build_changeset_metadata(assigns)

        assigns.item
        |> changeset_function.(params, metadata)
        |> Map.put(:action, :insert)
        |> Ecto.Changeset.apply_action(:insert)
      else
        {:ok, %{}}
      end

    with {:ok, data} <- result,
         selected_items <- Enum.filter(selected_items, &live_resource.can?(socket.assigns, action_key, &1)),
         {:ok, socket} <- action_to_confirm.module.handle(socket, selected_items, data) do
      socket
      |> assign(:show_form_errors, false)
      |> assign(:selected_items, [])
      |> assign(:select_all, false)
      |> push_patch(to: return_to)
      |> noreply()
    else
      {:error, changeset} ->
        form = Phoenix.Component.to_form(changeset, as: :change)

        socket
        |> assign(:show_form_errors, true)
        |> assign(:form, form)
        |> noreply()

      unexpected_return ->
        raise ArgumentError, """
        Invalid return value from #{inspect(action_to_confirm.module)}.handle/2.

        Expected: {:ok, socket} or {:error, changeset}
        Got: #{inspect(unexpected_return)}

        Item Actions with form fields must return {:ok, socket} or {:error, changeset}.
        """
    end
  end

  defp drop_readonly_changes(change, fields, assigns) do
    read_only =
      fields
      |> Enum.filter(&Backpex.Field.readonly?(&1, assigns))
      |> Enum.map(&Atom.to_string(&1.name))

    Map.drop(change, read_only)
  end

  defp drop_unused_changes(change) do
    change
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      if String.starts_with?(key, "_unused_"), do: acc, else: Map.put(acc, key, value)
    end)
  end

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
      {name, %{upload_key: upload_key} = field_options} = _field, acc ->
        %{put_upload_change: put_upload_change} = field_options

        uploaded_entries = uploaded_entries(socket, upload_key)
        removed_entries = Keyword.get(socket.assigns.removed_uploads, upload_key, [])

        change = put_upload_change.(socket, acc, socket.assigns.item, uploaded_entries, removed_entries, action)

        upload_used_input_data = Map.get(change, "#{to_string(name)}_used_input")
        used_input? = upload_used_input_data != "false"

        if uploaded_entries != {[], []} or removed_entries != [] or used_input? == true do
          change
          |> Map.drop(["_unused_#{to_string(name)}", "_unused_#{to_string(name)}_used_input"])
          |> Map.put("#{to_string(name)}_used_input", "true")
        else
          change
          |> Map.put("_unused_#{to_string(name)}", "")
          |> Map.put("#{to_string(name)}_used_input", "false")
        end

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
    Backpex.HTML.Resource.form_component(assigns)
  end
end
