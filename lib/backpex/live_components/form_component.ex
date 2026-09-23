defmodule Backpex.FormComponent do
  @moduledoc """
  The form live component.
  """
  use BackpexWeb, :html
  use Phoenix.LiveComponent

  alias Backpex.Field
  alias Backpex.ItemAction
  alias Backpex.LiveResource
  alias Backpex.Resource
  alias Backpex.ResourceAction
  alias Phoenix.Component

  require Backpex

  def update(assigns, socket) do
    socket
    |> assign(assigns)
    |> assign_new(:action_type, fn -> nil end)
    |> assign_new(:show_form_errors, fn -> false end)
    |> update_assigns()
    |> assign_form()
    |> ok()
  end

  # item action
  defp update_assigns(%{assigns: %{action_type: :item}} = socket) do
    %{action_to_confirm: action_to_confirm} = socket.assigns

    socket
    |> assign_new(:fields, fn -> action_to_confirm.module.fields() end)
  end

  # resource action
  defp update_assigns(%{assigns: %{action_type: :resource}} = socket) do
    %{resource_action: resource_action} = socket.assigns

    socket
    |> assign_new(:fields, fn -> resource_action.module.fields() end)
    |> assign(:form_actions, save: %{label: ResourceAction.name(resource_action, :label)})
    |> maybe_assign_uploads()
  end

  # default form
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

  defp apply_action(socket, action) when action in [:edit, :new] do
    live_resource = socket.assigns.live_resource

    assign(socket, :form_actions, live_resource.form_actions(socket.assigns, default_form_actions(live_resource)))
  end

  defp default_form_actions(live_resource) do
    save = [save: %{label: Backpex.__("Save", live_resource)}]

    if live_resource.config(:save_and_continue_button?),
      do: [{:continue, %{label: Backpex.__("Save & Continue editing", live_resource), soft: true}} | save],
      else: save
  end

  defp assign_form(socket) do
    changeset = socket.assigns.changeset
    form = Component.to_form(changeset, as: :change)

    assign(socket, :form, form)
  end

  def handle_event("validate", %{"change" => change, "_target" => target}, %{assigns: %{action_type: :item}} = socket) do
    %{assigns: %{action_item: action_item, fields: fields} = assigns} = socket

    changeset_function = fn item, changes, metadata ->
      assigns.action_to_confirm.module.changeset(item, changes, metadata)
    end

    target = Enum.at(target, 1)

    change =
      change
      |> drop_readonly_changes(fields, assigns)
      |> put_upload_change(socket, :validate)

    metadata = Resource.build_changeset_metadata(socket.assigns, target)

    changeset =
      action_item
      |> changeset_function.(change, metadata)
      |> Map.put(:action, :validate)

    form = Component.to_form(changeset, as: :change)

    send(self(), {:update_changeset, changeset})

    socket
    |> assign(:form, form)
    |> assign(:show_form_errors, false)
    |> noreply()
  end

  def handle_event("validate", %{"change" => change, "_target" => target}, socket) do
    %{live_resource: live_resource, fields: fields, item: item} = socket.assigns

    target = Enum.at(target, 1)
    assocs = Map.get(socket.assigns, :assocs, [])

    change =
      change
      |> drop_readonly_changes(fields, socket.assigns)
      |> put_upload_change(socket, :validate)

    opts = [target: target, assocs: assocs]
    changeset = Resource.change(item, change, fields, socket.assigns, live_resource, opts)

    form = Component.to_form(changeset, as: :change)

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
      socket.assigns.fields
      |> Enum.find(fn {_name, field_options} ->
        Map.has_key?(field_options, :upload_key) and Map.get(field_options, :upload_key) == upload_key
      end)

    removed_uploads =
      socket.assigns
      |> Map.get(:removed_uploads, [])
      |> Keyword.update(upload_key, [file_key], fn existing -> [file_key | existing] end)

    files =
      Backpex.Fields.Upload.existing_file_paths(
        field,
        socket.assigns.item,
        Keyword.get(removed_uploads, upload_key, [])
      )

    uploaded_files = Keyword.put(socket.assigns[:uploaded_files], upload_key, files)

    socket
    |> assign(:removed_uploads, removed_uploads)
    |> assign(:uploaded_files, uploaded_files)
    |> push_event("cancel-existing-entry:#{upload_key}", %{})
    |> noreply()
  end

  def handle_event("save", %{"action-key" => key, "change" => change}, %{assigns: %{action_type: :item}} = socket) do
    key = String.to_existing_atom(key)
    handle_form_item_action(socket, key, change)
  end

  def handle_event("save", %{"change" => change, "save-type" => save_type}, socket) do
    %{assigns: %{live_action: live_action, fields: fields} = assigns} = socket

    change =
      change
      |> put_upload_change(socket, :insert)
      |> drop_readonly_changes(fields, assigns)
      |> drop_unused_changes()

    handle_save(socket, live_action, change, form_action(socket, save_type))
  end

  def handle_event("save", %{"action-key" => key}, socket) do
    key = String.to_existing_atom(key)
    handle_form_item_action(socket, key, %{})
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

  # Only keys of the rendered form actions count; anything else from the client is ignored.
  defp form_action(%{assigns: %{form_actions: form_actions}}, save_type) do
    form_actions |> Keyword.keys() |> Enum.find(&(Atom.to_string(&1) == save_type))
  end

  defp form_action(_socket, _save_type), do: nil

  defp handle_save(socket, key, params, form_action \\ :save)

  defp handle_save(socket, :new, params, form_action) do
    %{assigns: %{live_resource: live_resource, fields: fields, item: item, live_action: live_action} = assigns} = socket

    opts = [
      assocs: Map.get(assigns, :assocs, []),
      after_save_fun: fn item ->
        handle_uploads(socket, item)
        live_resource.on_item_created(socket, item)

        {:ok, item}
      end
    ]

    case Resource.insert(item, params, fields, socket.assigns, live_resource, opts) do
      {:ok, item} ->
        return_to = return_to_path(form_action, live_resource, socket, socket.assigns, live_action, item)

        socket
        |> assign(:show_form_errors, false)
        |> clear_flash()
        |> put_flash(
          :info,
          Backpex.__(
            {"New %{resource} has been created successfully.", %{resource: assigns.live_resource.singular_name()}},
            live_resource
          )
        )
        |> push_navigate(to: return_to)
        |> noreply()

      {:error, changeset} when is_struct(changeset) ->
        form = Component.to_form(changeset, as: :change)

        send(self(), {:update_changeset, changeset})

        socket
        |> assign(:show_form_errors, true)
        |> assign(:form, form)
        |> noreply()
    end
  end

  defp handle_save(socket, :edit, params, form_action) do
    %{
      live_resource: live_resource,
      item: item,
      live_action: live_action,
      fields: fields
    } = socket.assigns

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
        return_to = return_to_path(form_action, live_resource, socket, socket.assigns, live_action, item)

        info_msg =
          Backpex.__(
            {"%{resource} has been edited successfully.", %{resource: live_resource.singular_name()}},
            live_resource
          )

        socket
        |> assign(:show_form_errors, false)
        |> clear_flash()
        |> put_flash(:info, info_msg)
        |> push_navigate(to: return_to)
        |> noreply()

      {:error, changeset} when is_struct(changeset) ->
        form = Component.to_form(changeset, as: :change)

        send(self(), {:update_changeset, changeset})

        socket
        |> assign(:show_form_errors, true)
        |> assign(:form, form)
        |> noreply()
    end
  end

  defp handle_save(socket, :resource_action, params, _form_action) do
    %{
      assigns:
        %{
          live_resource: live_resource,
          fields: fields,
          resource_action: resource_action,
          item: item,
          return_to: return_to
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
        form = Component.to_form(changeset, as: :change)

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

  defp handle_form_item_action(socket, action_key, params) do
    %{
      assigns:
        %{
          live_resource: live_resource,
          fields: fields,
          selected_items: selected_items,
          action_to_confirm: action_to_confirm,
          return_to: return_to
        } = assigns
    } = socket

    params = drop_readonly_changes(params, fields, assigns)

    result =
      if ItemAction.has_form?(action_to_confirm) do
        changeset_function = fn item, changes, metadata ->
          action_to_confirm.module.changeset(item, changes, metadata)
        end

        metadata = Resource.build_changeset_metadata(assigns)

        assigns.action_item
        |> changeset_function.(params, metadata)
        |> Map.put(:action, :insert)
        |> Ecto.Changeset.apply_action(:insert)
      else
        {:ok, %{}}
      end

    with {:ok, data} <- result,
         selected_items = Enum.filter(selected_items, &live_resource.can?(socket.assigns, action_key, &1)),
         {:ok, socket} <- action_to_confirm.module.handle(socket, selected_items, data) do
      socket
      |> assign(:show_form_errors, false)
      |> assign(:selected_items, [])
      |> assign(:select_all, false)
      |> push_navigate(to: return_to)
      |> noreply()
    else
      {:error, changeset} ->
        form = Component.to_form(changeset, as: :change)

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
    Field.drop_readonly_changes(change, fields, assigns)
  end

  defp drop_unused_changes(change) do
    change
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      if String.starts_with?(key, "_unused_"), do: acc, else: Map.put(acc, key, value)
    end)
  end

  defp return_to_path(:continue, live_resource, _socket, %{current_url: url}, :new, item) do
    primary_value = LiveResource.primary_value(item, live_resource)

    url
    |> URI.parse()
    |> Map.get(:path)
    |> Path.dirname()
    |> Kernel.<>("/#{primary_value}/edit")
  end

  defp return_to_path(:continue, _live_resource, _socket, %{current_url: url}, :edit, _item) do
    URI.parse(url).path
  end

  defp return_to_path(form_action, live_resource, socket, assigns, live_action, item) do
    live_resource.return_to(socket, assigns, live_action, form_action, item)
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
    for {_name, %{upload_key: upload_key} = field_options} = _field <- socket.assigns.fields,
        Map.has_key?(socket.assigns.uploads, upload_key) do
      consume_and_remove_uploads(socket, item, upload_key, field_options)
    end
  end

  defp handle_uploads(_socket, _item), do: :ok

  defp consume_and_remove_uploads(socket, item, upload_key, field_options) do
    %{consume_upload: consume_upload, remove_uploads: remove_uploads} = field_options

    consume_uploaded_entries(socket, upload_key, fn meta, entry ->
      consume_upload.(socket, item, meta, entry)
    end)

    removed_entries = Keyword.get(socket.assigns.removed_uploads, upload_key, [])
    remove_uploads.(socket, item, removed_entries)
  end

  def render(assigns) do
    Backpex.HTML.Resource.form_component(assigns)
  end
end
