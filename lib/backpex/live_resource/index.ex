defmodule Backpex.LiveResource.Index do
  @moduledoc false
  use BackpexWeb, :html

  import Phoenix.Component

  alias Backpex.Resource
  alias Backpex.LiveResource
  alias Backpex.ResourceAction
  alias Backpex.Adapters.Ecto, as: EctoAdapter
  alias Backpex.Router
  alias Phoenix.LiveView

  require Backpex

  def mount(params, session, socket, live_resource) do
    if LiveView.connected?(socket) do
      [server: server, topic: topic] = live_resource.pubsub()

      Phoenix.PubSub.subscribe(server, topic)
    end

    socket
    |> assign(:live_resource, live_resource)
    |> assign(:panels, live_resource.panels())
    |> assign(:fluid?, live_resource.config(:fluid?))
    |> assign(
      :create_button_label,
      Backpex.__({"New %{resource}", %{resource: live_resource.singular_name()}}, live_resource)
    )
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

  def handle_info({"backpex:" <> event, item}, socket) do
    handle_backpex_info({event, item}, socket)
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  defp handle_backpex_info({"created", _item}, socket) do
    {:noreply, refresh_items(socket)}
  end

  defp handle_backpex_info({"deleted", item}, socket) do
    %{items: items, live_resource: live_resource} = socket.assigns

    if Enum.filter(
         items,
         &(to_string(LiveResource.primary_value(&1, live_resource)) ==
             to_string(LiveResource.primary_value(item, live_resource)))
       ) != [] do
      {:noreply, refresh_items(socket)}
    else
      {:noreply, socket}
    end
  end

  defp handle_backpex_info({"updated", item}, socket) do
    {:noreply, update_item(socket, item)}
  end

  defp handle_backpex_info({_event, _item}, socket) do
    {:noreply, socket}
  end

  def handle_event("item-action", %{"action-key" => key, "item-id" => item_id}, socket) do
    %{items: items, live_resource: live_resource} = socket.assigns

    item =
      Enum.find(items, fn item -> to_string(LiveResource.primary_value(item, live_resource)) == to_string(item_id) end)

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
        Map.merge(query_options, %{per_page: per_page})
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
        Map.merge(query_options, %{search: search_input})
      )

    socket
    |> LiveView.push_patch(to: to, replace: true)
    |> noreply()
  end

  @impl Phoenix.LiveView
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
      |> Map.drop([Atom.to_string(LiveResource.empty_filter_key())])

    to =
      Router.get_path(
        socket,
        socket.assigns.live_resource,
        socket.assigns.params,
        :index,
        Map.put(query_options, :filters, filters)
      )

    socket
    |> assign(filters_changed: true)
    |> LiveView.push_patch(to: to)
    |> noreply()
  end

  def handle_event("update-selected-items", %{"id" => id}, socket) do
    %{selected_items: selected_items, live_resource: live_resource} = socket.assigns

    item =
      Enum.find(socket.assigns.items, fn item ->
        to_string(LiveResource.primary_value(item, live_resource)) == to_string(id)
      end)

    updated_selected_items =
      if Enum.member?(selected_items, item) do
        List.delete(selected_items, item)
      else
        [item | selected_items]
      end

    select_all = length(updated_selected_items) == length(socket.assigns.items)

    socket
    |> assign(:selected_items, updated_selected_items)
    |> assign(:select_all, select_all)
    |> noreply()
  end

  def handle_event("toggle-item-selection", _params, socket) do
    select_all = not socket.assigns.select_all
    selected_items = select_all && socket.assigns.items || []

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
    %{live_resource: live_resource, query_options: query_options, params: params} = socket.assigns

    new_query_options =
      Map.put(
        query_options,
        :filters,
        Map.get(query_options, :filters, %{})
        |> Map.delete(field)
        |> maybe_put_empty_filter(LiveResource.empty_filter_key())
      )

    to = Router.get_path(socket, live_resource, params, :index, new_query_options)

    socket
    |> LiveView.push_patch(to: to)
    |> assign(params: Map.merge(params, new_query_options))
    |> assign(query_options: new_query_options)
    |> assign(filters_changed: true)
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
    if Backpex.ItemAction.has_form?(action) do
      changeset_function = &action.module.changeset/3
      base_schema = action.module.base_schema(socket.assigns)

      metadata = Resource.build_changeset_metadata(socket.assigns)
      changeset = changeset_function.(base_schema, %{}, metadata)

      socket
      |> assign(:item, base_schema)
      |> assign(:changeset, changeset)
    else
      socket
      |> assign(:changeset, %{})
    end
    |> assign(:action_to_confirm, Map.put(action, :key, key))
    |> noreply()
  end

  defp handle_item_action(socket, action, key, items) do
    %{live_resource: live_resource} = socket.assigns
    items = Enum.filter(items, fn item -> live_resource.can?(socket.assigns, key, item) end)

    case action.module.handle(socket, items, %{}) do
      {:ok, socket} ->
        socket
        |> assign(action_to_confirm: nil)
        |> assign(selected_items: [])
        |> assign(select_all: false)
        |> noreply()

      unexpected_return ->
        raise ArgumentError, """
        Invalid return value from #{inspect(action.module)}.handle/3.

        Expected: {:ok, socket}
        Got: #{inspect(unexpected_return)}

        Item Actions with no form fields must return {:ok, socket}.
        """
    end
  end

  defp maybe_put_empty_filter(%{} = filters, empty_filter_key) when filters == %{} do
    Map.put(filters, Atom.to_string(empty_filter_key), true)
  end

  defp maybe_put_empty_filter(filters, _empty_filter_key) do
    filters
  end

  defp assign_active_fields(socket, session) do
    fields =
      socket.assigns.live_resource.validated_fields()
      |> LiveResource.filtered_fields_by_action(socket.assigns, :index)

    saved_fields = get_in(session, ["backpex", "column_toggle", "#{socket.assigns.live_resource}"]) || %{}

    active_fields =
      Enum.map(fields, fn {name, %{label: label}} ->
        {name,
         %{
           active: field_active?(name, saved_fields),
           label: label
         }}
      end)

    socket
    |> assign(:active_fields, active_fields)
  end

  defp field_active?(name, saved_fields) do
    case Map.get(saved_fields, Atom.to_string(name)) do
      "true" -> true
      "false" -> false
      _other -> true
    end
  end

  defp update_item(socket, item) do
    %{live_resource: live_resource, items: items} = socket.assigns

    item_primary_value = LiveResource.primary_value(item, live_resource)
    {:ok, item} = Resource.get(item_primary_value, socket.assigns, live_resource)

    items =
      Enum.map(items, &if(LiveResource.primary_value(&1, live_resource) == item_primary_value, do: item, else: &1))

    assign(socket, :items, items)
  end

  defp assign_metrics_visibility(socket, session) do
    value = get_in(session, ["backpex", "metric_visibility"]) || %{}

    socket
    |> assign(metric_visibility: value)
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
    |> assign(:page_title, socket.assigns.live_resource.plural_name())
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

    changeset_function = &action.module.changeset/3
    item = action.module.base_schema(socket.assigns)

    socket
    |> assign(:page_title, ResourceAction.name(action, :title))
    |> assign(:resource_action, action)
    |> assign(:resource_action_id, id)
    |> assign(:item, item)
    |> apply_index()
    |> assign(:changeset_function, changeset_function)
    |> assign_changeset(changeset_function, item, action.module.fields(), :resource_action)
  end

  defp apply_index(socket) do
    %{live_resource: live_resource, params: params} = socket.assigns

    if not live_resource.can?(socket.assigns, :index, nil), do: raise(Backpex.ForbiddenError)

    fields = live_resource.validated_fields() |> LiveResource.filtered_fields_by_action(socket.assigns, :index)

    per_page_options = live_resource.config(:per_page_options)
    per_page_default = live_resource.config(:per_page_default)
    init_order = live_resource.config(:init_order)

    filters = LiveResource.active_filters(socket.assigns)
    valid_filter_params = LiveResource.get_valid_filters_from_params(params, filters, LiveResource.empty_filter_key())

    adapter_config = live_resource.config(:adapter_config)

    count_criteria = [
      search: LiveResource.search_options(params, fields, adapter_config[:schema]),
      filters: LiveResource.filter_options(valid_filter_params, filters)
    ]

    {:ok, item_count} = Resource.count(count_criteria, socket.assigns, live_resource)

    per_page =
      params
      |> LiveResource.parse_integer("per_page", per_page_default)
      |> LiveResource.value_in_permitted_or_default(per_page_options, per_page_default)

    total_pages = LiveResource.calculate_total_pages(item_count, per_page)
    page = params |> LiveResource.parse_integer("page", 1) |> LiveResource.validate_page(total_pages)

    page_options = %{page: page, per_page: per_page}

    order_options = LiveResource.order_options_by_params(params, fields, init_order, socket.assigns)

    query_options =
      page_options
      |> Map.merge(order_options)
      |> maybe_put_search(params)
      |> Map.put(:filters, Map.get(valid_filter_params, "filters", %{}))

    socket
    |> assign(:item_count, item_count)
    |> assign(:query_options, query_options)
    |> assign(:init_order, init_order)
    |> assign(:total_pages, total_pages)
    |> assign(:per_page_options, per_page_options)
    |> assign(:filters, filters)
    |> assign(:orderable_fields, LiveResource.orderable_fields(fields))
    |> assign(:searchable_fields, LiveResource.searchable_fields(fields))
    |> assign(:resource_actions, live_resource.resource_actions())
    |> assign(:action_to_confirm, nil)
    |> assign(:selected_items, [])
    |> assign(:select_all, false)
    |> assign(:fields, fields)
    |> maybe_redirect_to_default_filters()
    |> assign_items()
    |> maybe_assign_metrics()
    |> apply_index_return_to()
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

  defp maybe_put_search(query_options, %{"search" => search} = _params)
       when is_nil(search) or search == "",
       do: query_options

  defp maybe_put_search(query_options, %{"search" => search} = _params),
    do: Map.put(query_options, :search, search)

  defp maybe_put_search(query_options, _params), do: query_options

  defp maybe_redirect_to_default_filters(%{assigns: %{filters_changed: false}} = socket) do
    %{live_resource: live_resource, query_options: query_options, params: params, filters: filters} = socket.assigns

    filters_with_defaults =
      filters
      |> Enum.filter(fn {_key, filter_config} ->
        Map.has_key?(filter_config, :default)
      end)

    # redirect to default filters if no filters are set and defaults are available
    if Map.get(query_options, :filters) == %{} and Enum.count(filters_with_defaults) > 0 do
      default_filter_options =
        filters_with_defaults
        |> Enum.map(fn {key, filter_config} ->
          {key, filter_config.default}
        end)
        |> Enum.into(%{}, fn {key, value} ->
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
    %{
      live_resource: live_resource,
      params: params,
      fields: fields,
      query_options: query_options
    } = socket.assigns

    adapter_config = live_resource.config(:adapter_config)
    filters = LiveResource.active_filters(socket.assigns)
    valid_filter_params = LiveResource.get_valid_filters_from_params(params, filters, LiveResource.empty_filter_key())

    count_criteria = [
      search: LiveResource.search_options(params, fields, adapter_config[:schema]),
      filters: LiveResource.filter_options(valid_filter_params, filters)
    ]

    {:ok, item_count} = Resource.count(count_criteria, socket.assigns, live_resource)
    %{page: page, per_page: per_page} = query_options
    total_pages = LiveResource.calculate_total_pages(item_count, per_page)
    new_query_options = Map.put(query_options, :page, LiveResource.validate_page(page, total_pages))

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
      fields: fields,
      query_options: query_options,
      metric_visibility: metric_visibility
    } = socket.assigns

    adapter_config = live_resource.config(:adapter_config)
    filters = LiveResource.active_filters(socket.assigns)

    metrics =
      socket.assigns.live_resource.metrics()
      |> Enum.map(fn {key, metric} ->
        criteria = [
          search: LiveResource.search_options(query_options, fields, adapter_config[:schema]),
          filters: LiveResource.filter_options(query_options, filters)
        ]

        query = EctoAdapter.list_query(criteria, socket.assigns, live_resource)

        case Backpex.Metric.metrics_visible?(metric_visibility, live_resource) do
          true ->
            data =
              query
              |> Ecto.Query.exclude(:select)
              |> Ecto.Query.exclude(:preload)
              |> Ecto.Query.exclude(:group_by)
              |> metric.module.query(metric.select, adapter_config[:repo])

            {key, Map.put(metric, :data, data)}

          _visible ->
            {key, metric}
        end
      end)

    socket
    |> assign(metrics: metrics)
  end

  defp assign_items(socket) do
    criteria = LiveResource.build_criteria(socket.assigns)
    {:ok, items} = Resource.list(criteria, socket.assigns, socket.assigns.live_resource)

    assign(socket, :items, items)
  end
end
