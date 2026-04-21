defmodule Backpex.LiveResource.Index do
  @moduledoc false
  use BackpexWeb, :html

  import Phoenix.Component

  alias Backpex.Adapters.Ecto, as: EctoAdapter
  alias Backpex.FilterValidation
  alias Backpex.LiveResource
  alias Backpex.PaginationValidation
  alias Backpex.Preferences
  alias Backpex.Preferences.Keys, as: PreferenceKeys
  alias Backpex.Preferences.LiveView, as: PreferenceLiveView
  alias Backpex.Resource
  alias Backpex.Router

  alias Phoenix.LiveView

  require Backpex

  def mount(params, session, socket, live_resource) do
    socket
    |> LiveResource.maybe_subscribe_to_pubsub(live_resource)
    |> assign(:live_resource, live_resource)
    |> assign(:panels, live_resource.panels())
    |> assign(:fluid?, live_resource.config(:fluid?))
    |> assign(:fields, live_resource.fields(socket.assigns.live_action, socket.assigns))
    |> assign(
      :create_button_label,
      Backpex.__({"New %{resource}", %{resource: live_resource.singular_name()}}, live_resource)
    )
    |> assign_persisted_index_state(session)
    |> assign_metrics_visibility(session)
    |> assign_filters_changed_status(params)
    |> assign_active_fields(session)
    |> ok()
  end

  def handle_params(params, _url, socket) do
    socket
    |> assign(:params, params)
    |> assign_item_actions()
    |> apply_action(socket.assigns.live_action)
    |> noreply()
  end

  def render(assigns) do
    Backpex.HTML.Resource.resource_index(assigns)
  end

  def handle_info({"backpex:created", _item}, socket) do
    socket
    |> refresh_items()
    |> noreply()
  end

  def handle_info({"backpex:updated", item}, socket) do
    socket
    |> update_item(item)
    |> noreply()
  end

  def handle_info({"backpex:deleted", item}, socket) do
    %{items: items, live_resource: live_resource} = socket.assigns

    primary_value = LiveResource.primary_value(item, live_resource)

    case find_item_by_primary_value(items, primary_value, live_resource) do
      nil ->
        noreply(socket)

      _item ->
        socket
        |> refresh_items()
        |> noreply()
    end
  end

  # credo:disable-for-this-file Credo.Check.Design.DuplicatedCode
  def handle_info({:update_changeset, changeset}, socket) do
    socket
    |> assign(:changeset, changeset)
    |> noreply()
  end

  # credo:disable-for-this-file Credo.Check.Design.DuplicatedCode
  def handle_info({:put_assoc, {key, value} = _assoc}, socket) do
    changeset = Ecto.Changeset.put_assoc(socket.assigns.changeset, key, value)
    assocs = Map.get(socket.assigns, :assocs, []) |> Keyword.put(key, value)

    socket
    |> assign(:assocs, assocs)
    |> assign(:changeset, changeset)
    |> noreply()
  end

  def handle_info(_event, socket) do
    noreply(socket)
  end

  def handle_event("change-filter", params, socket) do
    query_options = socket.assigns.query_options

    # Merge new filter values with existing ones
    filters =
      Map.get(query_options, :filters, %{})
      |> Map.merge(params["filters"] || %{})
      # Filter out empty values
      |> Enum.reject(fn
        {_filter, ""} -> true
        {_filter, nil} -> true
        {_filter, []} -> true
        {_filter, %{"start" => "", "end" => ""}} -> true
        {_filter, %{"start" => nil, "end" => nil}} -> true
        _filter_params -> false
      end)
      |> Map.new()

    apply_filter_change(socket, filters)
  end

  def handle_event("item-action", %{"action-key" => key, "item-id" => item_id}, socket) do
    %{items: items, live_resource: live_resource} = socket.assigns

    item = find_item_by_primary_value(items, item_id, live_resource)

    socket
    |> assign(selected_items: [item])
    |> maybe_handle_item_action(key)
  end

  def handle_event("item-action", %{"action-key" => key}, socket) do
    maybe_handle_item_action(socket, key)
  end

  def handle_event("select-page-size", %{"select_per_page" => %{"value" => per_page}}, socket) do
    %{query_options: query_options, params: params} = socket.assigns

    per_page = String.to_integer(per_page)

    to =
      Router.get_path(
        socket,
        socket.assigns.live_resource,
        params,
        :index,
        Map.put(query_options, :per_page, per_page)
      )

    socket
    |> LiveView.push_patch(to: to, replace: true)
    |> noreply()
  end

  def handle_event("index-search", %{"index_search" => %{"value" => search_input}}, socket) do
    %{query_options: query_options, params: params} = socket.assigns

    to =
      Router.get_path(
        socket,
        socket.assigns.live_resource,
        params,
        :index,
        Map.put(query_options, :search, search_input)
      )

    socket
    |> LiveView.push_patch(to: to, replace: true)
    |> noreply()
  end

  def handle_event("filter-preset-selected", %{"field" => field, "preset-index" => preset_index} = _params, socket) do
    query_options = socket.assigns.query_options
    preset_index = String.to_integer(preset_index)
    field_atom = String.to_existing_atom(field)

    get_preset_values =
      socket.assigns
      |> get_in([:filters, field_atom, :presets])
      |> Enum.at(preset_index)
      |> Map.get(:values)

    filters =
      Map.get(query_options, :filters, %{})
      |> Map.put(field, get_preset_values.())

    apply_filter_change(socket, filters)
  end

  def handle_event("update-selected-items", %{"id" => id}, socket) do
    %{selected_items: selected_items, live_resource: live_resource, items: items} = socket.assigns

    item = find_item_by_primary_value(items, id, live_resource)

    updated_selected_items =
      if Enum.member?(selected_items, item) do
        List.delete(selected_items, item)
      else
        [item | selected_items]
      end

    select_all = length(updated_selected_items) == length(items)

    socket
    |> assign(:selected_items, updated_selected_items)
    |> assign(:select_all, select_all)
    |> noreply()
  end

  def handle_event("toggle-item-selection", _params, socket) do
    select_all = not socket.assigns.select_all
    selected_items = (select_all && socket.assigns.items) || []

    socket
    |> assign(:select_all, select_all)
    |> assign(:selected_items, selected_items)
    |> noreply()
  end

  def handle_event("cancel-action-confirm", _params, socket) do
    socket
    |> assign(:item, nil)
    |> assign(:changeset, nil)
    |> assign(:action_to_confirm, nil)
    |> noreply()
  end

  def handle_event("clear-filter", %{"field" => field}, socket) do
    filters =
      socket.assigns.query_options
      |> Map.get(:filters, %{})
      |> Map.delete(field)

    apply_filter_change(socket, filters)
  end

  def handle_event("toggle_column", %{"field" => field}, socket) do
    field_atom = String.to_existing_atom(field)
    active_fields = socket.assigns.active_fields

    updated_fields =
      Enum.map(active_fields, fn
        {^field_atom, config} -> {field_atom, %{config | active: !config.active}}
        other -> other
      end)

    columns =
      Map.new(updated_fields, fn {k, %{active: v}} ->
        {Atom.to_string(k), v}
      end)

    live_resource = socket.assigns.live_resource

    socket
    |> assign(:active_fields, updated_fields)
    |> maybe_push_columns(live_resource, columns)
    |> noreply()
  end

  def handle_event("toggle_metrics", _params, socket) do
    %{live_resource: live_resource, metric_visibility: metric_visibility} = socket.assigns

    resource_key_str = to_string(live_resource)
    current_visible = Map.get(metric_visibility, resource_key_str, true)
    new_visible = !current_visible

    updated_visibility = Map.put(metric_visibility, resource_key_str, new_visible)
    resource_key = PreferenceKeys.metrics_visible(live_resource)

    socket
    |> assign(:metric_visibility, updated_visibility)
    |> PreferenceLiveView.push_write(resource_key, new_visible)
    |> maybe_assign_metrics()
    |> noreply()
  end

  defp maybe_handle_item_action(socket, key) do
    key = String.to_existing_atom(key)
    action = socket.assigns.item_actions[key]
    items = socket.assigns.selected_items

    if Backpex.ItemAction.has_confirm_modal?(action) do
      open_action_confirm_modal(socket, action, key)
    else
      handle_item_action(socket, action, key, items)
    end
  end

  defp open_action_confirm_modal(socket, action, key) do
    socket
    |> Backpex.ItemAction.assign_action_changeset(action)
    |> assign(:action_to_confirm, Map.put(action, :key, key))
    |> noreply()
  end

  defp handle_item_action(socket, action, key, items) do
    Backpex.ItemAction.handle_item_action(socket, action, key, items, fn socket ->
      socket
      |> assign(action_to_confirm: nil)
      |> assign(selected_items: [])
      |> assign(select_all: false)
      |> noreply()
    end)
  end

  defp find_item_by_primary_value(items, primary_value, live_resource) do
    Enum.find(items, fn item ->
      to_string(LiveResource.primary_value(item, live_resource)) == to_string(primary_value)
    end)
  end

  defp assign_active_fields(socket, session) do
    %{fields: fields, live_resource: live_resource} = socket.assigns

    saved_columns =
      if persist_enabled?(live_resource, :columns) do
        resource_key = PreferenceKeys.columns(live_resource)
        Preferences.get(session, resource_key, default: %{})
      else
        %{}
      end

    active_fields =
      Enum.map(fields, fn {name, %{label: label}} ->
        active = Map.get(saved_columns, Atom.to_string(name), true)
        {name, %{active: active, label: label}}
      end)

    assign(socket, :active_fields, active_fields)
  end

  defp assign_persisted_index_state(socket, session) do
    %{live_resource: live_resource} = socket.assigns

    persisted = %{
      order: read_persisted(:order, live_resource, session),
      filters: read_persisted(:filters, live_resource, session)
    }

    assign(socket, :backpex_persisted_index_state, persisted)
  end

  defp read_persisted(:order, live_resource, session) do
    if persist_enabled?(live_resource, :order) do
      Preferences.get(session, PreferenceKeys.order(live_resource))
    end
  end

  defp read_persisted(:filters, live_resource, session) do
    if persist_enabled?(live_resource, :filters) do
      Preferences.get(session, PreferenceKeys.filters(live_resource))
    end
  end

  defp persist_enabled?(live_resource, what) do
    what in (live_resource.config(:persist) || [])
  end

  defp maybe_push_columns(socket, live_resource, columns) do
    if persist_enabled?(live_resource, :columns) do
      PreferenceLiveView.push_write(socket, PreferenceKeys.columns(live_resource), columns)
    else
      socket
    end
  end

  defp apply_filter_change(socket, new_filters) do
    %{live_resource: live_resource, query_options: query_options, params: params} = socket.assigns

    to =
      Router.get_path(
        socket,
        live_resource,
        params,
        :index,
        Map.put(query_options, :filters, new_filters)
      )

    socket
    |> maybe_push_filters(live_resource, new_filters)
    |> assign(filters_changed: true)
    |> LiveView.push_patch(to: to)
    |> noreply()
  end

  defp maybe_push_filters(socket, live_resource, filters) do
    if persist_enabled?(live_resource, :filters) do
      persisted = socket.assigns.backpex_persisted_index_state

      socket
      |> PreferenceLiveView.push_write(PreferenceKeys.filters(live_resource), filters)
      |> assign(:backpex_persisted_index_state, %{persisted | filters: filters})
    else
      socket
    end
  end

  defp update_item(socket, item) do
    %{live_resource: live_resource, fields: fields, items: items} = socket.assigns

    primary_value = LiveResource.primary_value(item, live_resource)
    primary_value_str = to_string(primary_value)
    {:ok, updated_item} = Resource.get(primary_value, fields, socket.assigns, live_resource)

    updated_items =
      Enum.map(items, fn current_item ->
        if to_string(LiveResource.primary_value(current_item, live_resource)) == primary_value_str do
          updated_item
        else
          current_item
        end
      end)

    assign(socket, :items, updated_items)
  end

  defp assign_metrics_visibility(socket, session) do
    %{live_resource: live_resource} = socket.assigns
    visible = Preferences.get(session, PreferenceKeys.metrics_visible(live_resource), default: true)

    assign(socket, :metric_visibility, %{to_string(live_resource) => visible})
  end

  defp assign_filters_changed_status(socket, params) do
    %{assigns: %{live_action: live_action}} = socket

    socket
    |> assign(:filters_changed, live_action == :index and params["filters_changed"] == "true")
  end

  defp assign_item_actions(socket) do
    item_actions = Backpex.ItemAction.default_actions() |> socket.assigns.live_resource.item_actions()
    assign(socket, :item_actions, item_actions)
  end

  defp apply_action(socket, :index) do
    socket
    |> apply_index()
    |> assign(:item, nil)
  end

  defp apply_action(socket, :resource_action) do
    %{live_resource: live_resource} = socket.assigns

    id =
      socket.assigns.params["backpex_id"]
      |> URI.decode()
      |> String.to_existing_atom()

    action = live_resource.resource_actions()[id]

    if not live_resource.can?(socket.assigns, id, nil), do: raise(Backpex.ForbiddenError)

    changeset_function = fn item, changes, metadata -> action.module.changeset(item, changes, metadata) end
    item = action.module.base_schema(socket.assigns)

    socket
    |> assign(:resource_action, action)
    |> assign(:resource_action_id, id)
    |> assign(:item, item)
    |> apply_index()
    |> assign(:changeset_function, changeset_function)
    |> assign_changeset(changeset_function, item, action.module.fields(), :resource_action)
  end

  defp apply_index(socket) do
    %{live_resource: live_resource, params: params, fields: fields} = socket.assigns
    persisted = socket.assigns[:backpex_persisted_index_state] || %{order: nil, filters: nil}

    if not live_resource.can?(socket.assigns, :index, nil), do: raise(Backpex.ForbiddenError)

    per_page_options = live_resource.config(:per_page_options)
    per_page_default = live_resource.config(:per_page_default)
    init_order = live_resource.config(:init_order)
    init_order = LiveResource.resolve_init_order(init_order, socket.assigns)
    init_order = maybe_override_init_order(init_order, params, persisted.order)

    filters = LiveResource.active_filters(socket.assigns)
    schema = live_resource.adapter_config(:schema)
    orderable_fields = LiveResource.orderable_fields(fields)

    # Build filter changeset from URL params and extract valid values
    raw_filter_params =
      case Map.get(params, "filters") do
        value when is_map(value) -> value
        _other -> fallback_filter_params(persisted.filters)
      end

    filter_changeset = FilterValidation.build_changeset(raw_filter_params, filters, socket.assigns)
    filter_values = FilterValidation.valid_values(filter_changeset)
    filter_form = to_form(filter_changeset, as: :filters)

    # Validate pagination and sorting params (page clamping happens after we know item_count)
    query_options =
      PaginationValidation.build(params,
        per_page_default: per_page_default,
        per_page_options: per_page_options,
        orderable_fields: orderable_fields,
        init_order: init_order
      )

    count_criteria = [
      search: LiveResource.search_options(params, fields, schema),
      filter_values: filter_values,
      filter_configs: filters
    ]

    {:ok, item_count} = Resource.count(count_criteria, fields, socket.assigns, live_resource)
    total_pages = LiveResource.calculate_total_pages(item_count, query_options.per_page)

    # Clamp page to valid range now that we know total_pages
    page = PaginationValidation.clamp_page(query_options.page, total_pages)
    query_options = %{query_options | page: page}

    query_options =
      query_options
      |> maybe_put_search(params)
      |> Map.put(:filters, raw_filter_params)

    socket
    |> assign(:page_title, socket.assigns.live_resource.plural_name())
    |> assign(:item_count, item_count)
    |> assign(:query_options, query_options)
    |> assign(:init_order, init_order)
    |> assign(:total_pages, total_pages)
    |> assign(:per_page_options, per_page_options)
    |> assign(:filters, filters)
    |> assign(:filter_form, filter_form)
    |> assign(:filter_values, filter_values)
    |> assign(:orderable_fields, orderable_fields)
    |> assign(:searchable_fields, LiveResource.searchable_fields(fields))
    |> assign(:resource_actions, live_resource.resource_actions())
    |> assign(:action_to_confirm, nil)
    |> assign(:selected_items, [])
    |> assign(:select_all, false)
    |> maybe_redirect_to_default_filters()
    |> assign_items()
    |> maybe_assign_metrics()
    |> maybe_persist_order(query_options)
    |> apply_index_return_to()
  end

  defp maybe_override_init_order(init_order, _params, nil), do: init_order

  defp maybe_override_init_order(init_order, params, stored_order) do
    cond do
      Map.has_key?(params, "order_by") or Map.has_key?(params, "order_direction") ->
        init_order

      match?(%{"by" => by, "direction" => dir} when is_binary(by) and is_binary(dir), stored_order) ->
        parse_stored_order(stored_order) || init_order

      true ->
        init_order
    end
  end

  defp parse_stored_order(%{"by" => by, "direction" => direction}) do
    %{by: String.to_existing_atom(by), direction: String.to_existing_atom(direction)}
  rescue
    ArgumentError -> nil
  end

  defp parse_stored_order(_other), do: nil

  defp fallback_filter_params(stored) when is_map(stored), do: stored
  defp fallback_filter_params(_other), do: %{}

  defp maybe_persist_order(socket, query_options) do
    %{live_resource: live_resource, backpex_persisted_index_state: persisted} = socket.assigns

    if persist_enabled?(live_resource, :order) do
      value = %{
        "by" => Atom.to_string(query_options.order_by),
        "direction" => Atom.to_string(query_options.order_direction)
      }

      if persisted.order == value do
        socket
      else
        socket
        |> PreferenceLiveView.push_write(PreferenceKeys.order(live_resource), value)
        |> assign(:backpex_persisted_index_state, %{persisted | order: value})
      end
    else
      socket
    end
  end

  defp apply_index_return_to(socket) do
    %{live_resource: live_resource, params: params, query_options: query_options} = socket.assigns

    socket
    |> assign(:return_to, Router.get_path(socket, live_resource, params, :index, query_options))
  end

  # TODO: move to common module
  defp assign_changeset(socket, changeset_function, item, fields, live_action) do
    metadata = Resource.build_changeset_metadata(socket.assigns)
    changeset = changeset_function.(item, LiveResource.default_attrs(live_action, fields, socket.assigns), metadata)

    assign(socket, :changeset, changeset)
  end

  defp maybe_put_search(query_options, %{"search" => search} = _params) when is_nil(search) or search == "",
    do: query_options

  defp maybe_put_search(query_options, %{"search" => search} = _params), do: Map.put(query_options, :search, search)

  defp maybe_put_search(query_options, _params), do: query_options

  defp maybe_redirect_to_default_filters(%{assigns: %{filters_changed: false}} = socket) do
    %{live_resource: live_resource, query_options: query_options, params: params, filters: filters} = socket.assigns

    filters_with_defaults =
      filters
      |> Enum.filter(fn {_key, filter_config} ->
        Map.has_key?(filter_config, :default)
      end)

    # redirect to default filters if no filters are set and defaults are available
    if Map.get(query_options, :filters) == %{} and not Enum.empty?(filters_with_defaults) do
      default_filter_options =
        filters_with_defaults
        |> Enum.map(fn {key, filter_config} ->
          {key, filter_config.default}
        end)
        |> Map.new(fn {key, value} ->
          {Atom.to_string(key), value}
        end)

      # redirect with updated query options
      options = Map.put(query_options, :filters, default_filter_options)
      to = Router.get_path(socket, live_resource, params, :index, options)
      LiveView.push_navigate(socket, to: to)
    else
      socket
    end
  end

  defp maybe_redirect_to_default_filters(socket) do
    socket
  end

  defp refresh_items(socket) do
    %{live_resource: live_resource, params: params, query_options: query_options, fields: fields} = socket.assigns

    schema = live_resource.adapter_config(:schema)
    filters = LiveResource.active_filters(socket.assigns)

    # Use the already-validated filter_values from assigns
    filter_values = Map.get(socket.assigns, :filter_values, %{})

    count_criteria = [
      search: LiveResource.search_options(params, fields, schema),
      filter_values: filter_values,
      filter_configs: filters
    ]

    {:ok, item_count} = Resource.count(count_criteria, fields, socket.assigns, live_resource)
    %{page: page, per_page: per_page} = query_options
    total_pages = LiveResource.calculate_total_pages(item_count, per_page)
    new_query_options = Map.put(query_options, :page, PaginationValidation.clamp_page(page, total_pages))

    socket
    |> assign(:item_count, item_count)
    |> assign(:total_pages, total_pages)
    |> assign(:query_options, new_query_options)
    |> assign_items()
    |> maybe_assign_metrics()
  end

  defp maybe_assign_metrics(socket) do
    %{
      live_resource: live_resource,
      query_options: query_options,
      metric_visibility: metric_visibility,
      fields: fields
    } = socket.assigns

    repo = live_resource.adapter_config(:repo)
    schema = live_resource.adapter_config(:schema)
    filters = LiveResource.active_filters(socket.assigns)

    # Use the already-validated filter_values from assigns
    filter_values = Map.get(socket.assigns, :filter_values, %{})

    metrics =
      socket.assigns.live_resource.metrics()
      |> Enum.map(fn {key, metric} ->
        criteria = [
          search: LiveResource.search_options(query_options, fields, schema),
          filter_values: filter_values,
          filter_configs: filters
        ]

        query = EctoAdapter.list_query(criteria, fields, socket.assigns, live_resource)

        case Backpex.Metric.metrics_visible?(metric_visibility, live_resource) do
          true ->
            data =
              query
              |> Ecto.Query.exclude(:select)
              |> Ecto.Query.exclude(:preload)
              |> Ecto.Query.exclude(:group_by)
              |> metric.module.query(metric.select, repo)

            {key, Map.put(metric, :data, data)}

          _visible ->
            {key, metric}
        end
      end)

    socket
    |> assign(metrics: metrics)
  end

  defp assign_items(socket) do
    %{assigns: %{live_resource: live_resource, fields: fields} = assigns} = socket

    {:ok, items} =
      assigns
      |> LiveResource.build_criteria()
      |> Resource.list(fields, assigns, live_resource)

    assign(socket, :items, items)
  end
end
