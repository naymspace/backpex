defmodule Backpex.HTML.Resource do
  @moduledoc """
  Contains all Backpex resource components.
  """
  use BackpexWeb, :html

  import Phoenix.LiveView.TagEngine
  import Backpex.HTML.Form
  import Backpex.HTML.Layout

  alias Backpex.LiveResource
  alias Backpex.ResourceAction
  alias Backpex.Router

  embed_templates("resource/*")

  @doc """
  Renders a resource table.
  """
  @doc type: :component

  attr :socket, :any, required: true
  attr :live_resource, :any, required: true, doc: "module of the live resource"
  attr :params, :string, required: true, doc: "query parameters"
  attr :query_options, :map, default: %{}, doc: "query options"
  attr :fields, :list, required: true, doc: "list of fields to be displayed in the table on index view"
  attr :orderable_fields, :list, default: [], doc: "list of orderable fields"
  attr :searchable_fields, :list, default: [], doc: "list of searchable fields"
  attr :items, :list, default: [], doc: "items that will be displayed in the table"
  attr :active_fields, :list, required: true, doc: "list of active fields"
  attr :selected_items, :list, required: true, doc: "list of selected items"

  def resource_index_table(assigns)

  @doc """
  Renders a link to change the order direction for a given column.
  """
  @doc type: :component

  attr :socket, :map, required: true
  attr :live_resource, :any, required: true, doc: "module of the live resource"
  attr :params, :string, required: true, doc: "query parameters"
  attr :query_options, :map, required: true, doc: "query options"
  attr :label, :string, required: true, doc: "label to be displayed on the link"
  attr :name, :atom, required: true, doc: "name of the column the link should change order for"

  def order_link(assigns) do
    order_direction =
      if assigns.name == assigns.query_options.order_by do
        toggle_order_direction(assigns.query_options.order_direction)
      else
        :asc
      end

    assigns =
      assigns
      |> assign(:next_order_direction, order_direction)

    ~H"""
    <.link
      class="flex items-center space-x-1"
      patch={
        Router.get_path(
          @socket,
          @live_resource,
          @params,
          :index,
          Map.merge(@query_options, %{order_direction: @next_order_direction, order_by: @name})
        )
      }
      replace
    >
      <p>{@label}</p>
      <%= if @name == @query_options.order_by do %>
        {order_icon(assigns, @query_options.order_direction)}
      <% end %>
    </.link>
    """
  end

  defp order_icon(assigns, :asc) do
    ~H"""
    <Backpex.HTML.CoreComponents.icon name="hero-arrow-up-solid" class="h-4 w-4" />
    """
  end

  defp order_icon(assigns, :desc) do
    ~H"""
    <Backpex.HTML.CoreComponents.icon name="hero-arrow-down-solid" class="h-4 w-4" />
    """
  end

  @doc """
  Renders the field of the given resource.
  """
  @doc type: :component

  attr :name, :string, required: true, doc: "name / key of the item field"
  attr :item, :map, required: true, doc: "the item which provides the value to be rendered"
  attr :fields, :list, required: true, doc: "list of all fields provided by the resource configuration"

  def resource_field(assigns) do
    %{name: name, item: item, fields: fields, live_resource: live_resource} = assigns

    {_name, field_options} = field = Enum.find(fields, fn {field_name, _field_options} -> field_name == name end)

    readonly =
      not live_resource.can?(assigns, :edit, item) or
        Backpex.Field.readonly?(field_options, assigns)

    assigns =
      assigns
      |> assign(:field, field)
      |> assign(:field_options, field_options)
      |> assign(:value, Map.get(item, name))
      |> assign(:type, :index)
      |> assign(:readonly, readonly)
      |> assign(:primary_key, Map.get(item, live_resource.config(:primary_key)))

    ~H"""
    <.live_component
      id={"resource_#{@name}_#{@primary_key}"}
      module={@field_options.module}
      type={@type}
      {Map.drop(assigns, [:socket, :flash, :myself, :uploads])}
    />
    """
  end

  @doc """
  Renders a resource form field.
  """
  @doc type: :component

  attr :name, :string, required: true, doc: "name / key of the item field"
  attr :form, :map, required: true, doc: "form that will be used by the form field"
  attr :repo, :any, required: false, doc: "ecto repo"
  attr :uploads, :map, required: false, default: %{}, doc: "map that contains upload information"
  attr :fields, :list, required: true, doc: "list of all fields provided by the resource configuration"

  def resource_form_field(assigns) do
    %{name: name, fields: fields} = assigns

    {_name, field_options} = field = Enum.find(fields, fn {field_name, _field_options} -> field_name == name end)

    assigns =
      assigns
      |> assign(:field, field)
      |> assign(:field_options, field_options)
      |> assign(:type, :form)

    ~H"""
    <.live_component
      id={"resource_#{@name}"}
      module={@field_options.module}
      lv_uploads={assigns[:uploads]}
      type={@type}
      {Map.drop(assigns, [:socket, :flash, :myself, :uploads])}
    />
    """
  end

  @doc """
  Renders form with a search field. Emits the `simple-search-input` event on change.
  """
  @doc type: :component

  attr :searchable_fields, :list,
    default: [],
    doc: "The fields that can be searched. Here only used to hide the component when empty."

  attr :full_text_search, :string, default: nil, doc: "full text search column name"
  attr :value, :string, required: true, doc: "value binding for the search input"
  attr :placeholder, :string, required: true, doc: "placeholder for the search input"

  def index_search_form(assigns) do
    form = to_form(%{"value" => assigns.value}, as: :index_search)
    search_enabled = not is_nil(assigns.full_text_search) or assigns.searchable_fields != []

    assigns =
      assigns
      |> assign(:search_enabled, search_enabled)
      |> assign(:form, form)

    ~H"""
    <.form :if={@search_enabled} id="index-search-form" for={@form} phx-change="index-search" phx-submit="index-search">
      <input
        name={@form[:value].name}
        class="input input-sm"
        placeholder={@placeholder}
        phx-debounce="200"
        value={@form[:value].value}
      />
    </.form>
    """
  end

  @doc """
  Renders the index filters if the `filter/0` callback is defined in the resource.
  """
  @doc type: :component

  attr :live_resource, :any, required: true, doc: "module of the live resource"
  attr :filter_options, :map, required: true, doc: "filter options"
  attr :filters, :list, required: true, doc: "list of active filters"

  def index_filter(assigns) do
    computed = [
      filter_count: Enum.count(assigns.filter_options),
      filter_icon_class:
        if(assigns.filter_options != %{},
          do: "text-primary group-hover:text-primary-content",
          else: "text-primary/75 group-hover:text-primary-content"
        )
    ]

    assigns = assign(assigns, computed)

    ~H"""
    <div :if={@filters != []} class="dropdown">
      <div class="indicator">
        <span :if={@filter_count > 0} class="indicator-item badge badge-secondary">
          {@filter_count}
        </span>
        <label tabindex="0" class="btn btn-sm btn-outline ring-base-content/10 border-0 ring-1">
          <Backpex.HTML.CoreComponents.icon name="hero-funnel-solid" class={["mr-2 h-5 w-5", @filter_icon_class]} />
          {Backpex.translate("Filters")}
        </label>
      </div>
      <div tabindex="0" class="dropdown-content z-[1] menu bg-base-100 rounded-box p-4 shadow">
        <.index_filter_forms filters={@filters} filter_options={@filter_options} />
      </div>
    </div>
    <Backpex.HTML.CoreComponents.filter_badge
      :for={{key, value} <- @filter_options}
      filter_name={key}
      clear_event="clear-filter"
      label={Keyword.get(@filters, String.to_existing_atom(key)).module.label()}
    >
      {component(
        &Keyword.get(@filters, String.to_existing_atom(key)).module.render/1,
        [value: value],
        {__ENV__.module, __ENV__.function, __ENV__.file, __ENV__.line}
      )}
    </Backpex.HTML.CoreComponents.filter_badge>
    """
  end

  defp index_filter_forms(assigns) do
    ~H"""
    <div class="space-y-5">
      <div :for={{field, filter} <- @filters}>
        <% value = Map.get(@filter_options, Atom.to_string(field), nil) %>
        <.form :let={f} for={to_form(%{}, as: :filters)} phx-change="change-filter" phx-submit="change-filter">
          <div>
            <div class="relative flex w-full flex-wrap justify-start gap-2">
              <div class="text-base-content text-sm font-medium">{Map.get(filter, :label, filter.module.label())}</div>
              <.maybe_clear_button field={field} value={value} />
            </div>
            <div class="flex gap-4">
              <div class="w-[240px]">
                {component(
                  &filter.module.render_form/1,
                  [field: field, value: value, form: f],
                  {__ENV__.module, __ENV__.function, __ENV__.file, __ENV__.line}
                )}
              </div>
              <.filter_presets field={field} presets={Map.get(filter, :presets)} />
            </div>
          </div>
        </.form>
      </div>
    </div>
    """
  end

  defp filter_presets(%{presets: nil} = assigns), do: ~H""

  defp filter_presets(assigns) do
    ~H"""
    <div class="min-w-[80px] mt-2">
      <div
        :for={{preset, index} <- Enum.with_index(@presets)}
        phx-click="filter-preset-selected"
        phx-value-field={@field}
        phx-value-preset-index={index}
        class="text-primary mb-1 cursor-pointer truncate text-xs font-medium"
      >
        {preset.label}
      </div>
    </div>
    """
  end

  defp maybe_clear_button(%{value: nil} = assigns), do: ~H""

  defp maybe_clear_button(assigns) do
    ~H"""
    <input
      value={Backpex.translate("clear")}
      type="button"
      phx-click="clear-filter"
      phx-value-field={@field}
      class="text-primary flex cursor-pointer items-center text-xs transition duration-75 hover:text-error hover:scale-105"
    />
    """
  end

  @doc """
  Renders the toggle columns dropdown.
  """
  @doc type: :component

  attr :socket, :any, required: true
  attr :active_fields, :list, required: true, doc: "list of active fields"
  attr :live_resource, :atom, required: true, doc: "the live resource"
  attr :current_url, :string, required: true, doc: "the current url"
  attr :class, :string, default: "", doc: "additional class to be added to the component"

  def toggle_columns(assigns) do
    form =
      to_form(%{"_resource" => assigns.live_resource, "_cookie_redirect_url" => assigns.current_url},
        as: :toggle_columns
      )

    assigns = assign(assigns, :form, form)

    ~H"""
    <div class={["dropdown", @class]}>
      <label tabindex="0" class="hover:cursor-pointer">
        <span class="sr-only">
          {Backpex.translate("Toggle columns")}
        </span>
        <Backpex.HTML.CoreComponents.icon
          name="hero-view-columns-solid"
          aria-hidden="true"
          class="text-base-content/50 h-5 w-5 hover:text-base-content"
        />
      </label>
      <div tabindex="0" class="dropdown-content menu bg-base-100 rounded-box min-w-52 max-w-72 p-4 shadow">
        <.form class="w-full" method="POST" for={@form} action={Router.cookie_path(@socket)}>
          <input type="hidden" name={@form[:_resource].name} value={@form[:_resource].value} />
          <input type="hidden" name={@form[:_cookie_redirect_url].name} value={@form[:_cookie_redirect_url].value} />
          <.toggle_columns_inputs active_fields={@active_fields} form={@form} />
          <button class="btn btn-sm btn-primary mt-4">
            {Backpex.translate("Save")}
          </button>
        </.form>
      </div>
    </div>
    """
  end

  @doc """
  Renders the toggle columns inputs.
  """
  @doc type: :component

  attr :form, :any, required: true, doc: "the form"
  attr :active_fields, :list, required: true, doc: "list of active fields to be displayed"

  def toggle_columns_inputs(assigns) do
    ~H"""
    <div class="flex flex-col space-y-1">
      <div :for={{name, %{active: active, label: label}} <- @active_fields}>
        <label class="flex cursor-pointer items-center">
          <input type="hidden" name={@form[name].name} value="false" />
          <input type="checkbox" name={@form[name].name} class="checkbox checkbox-sm checkbox-primary" checked={active} />
          <span class="label-text truncate pl-2">
            {label}
          </span>
        </label>
      </div>
    </div>
    """
  end

  @doc """
  Renders pagination info about the current page.
  """
  @doc type: :component

  attr :total, :integer, required: true, doc: "total number of items"
  attr :query_options, :map, required: true, doc: "query options"

  def pagination_info(assigns) do
    %{query_options: %{page: page, per_page: per_page}} = assigns

    from = (page - 1) * per_page + 1
    to = min(page * per_page, assigns.total)

    from_to_string = Backpex.translate({"Items %{from} to %{to}", %{from: from, to: to}})
    total_string = "(#{assigns.total} #{Backpex.translate("total")})"

    label = from_to_string <> " " <> total_string

    assigns = assign(assigns, :label, label)

    ~H"""
    <div :if={@total > 0} class="text-base-content pr-2 text-sm">
      {@label}
    </div>
    """
  end

  @doc """
  Renders pagination buttons. You are required to provide a `:page` pattern in the URL. It will be replaced
  with the corresponding page number.
  """
  @doc type: :component

  attr :current_page, :integer, required: true, doc: "current page number"
  attr :total_pages, :integer, required: true, doc: "number of total pages"
  attr :path, :string, required: true, doc: "path to be used for page links"

  def pagination(assigns) do
    assigns =
      assigns
      |> assign(:pagination_items, pagination_items(assigns.current_page, assigns.total_pages))

    ~H"""
    <div class="join">
      <.pagination_item
        :for={%{type: type, number: number} <- @pagination_items}
        class="join-item text-xs"
        type={type}
        number={number}
        current_page={@current_page}
        path={@path}
      />
    </div>
    """
  end

  attr :path, :string, required: true
  attr :current_page, :integer, required: true
  attr :type, :atom, required: true
  attr :number, :integer, default: nil, required: false
  attr :class, :string, default: nil

  defp pagination_item(%{type: :number} = assigns) do
    pagination_link = get_pagination_link(assigns.path, assigns.number)

    assigns = assign(assigns, :href, pagination_link)

    ~H"""
    <%= if @current_page == @number do %>
      <button class={["btn btn-active", @class]} aria-disabled="true">
        {Integer.to_string(@number)}
      </button>
    <% else %>
      <.link href={@href}>
        <button class={["btn bg-base-100", @class]}>
          {Integer.to_string(@number)}
        </button>
      </.link>
    <% end %>
    """
  end

  defp pagination_item(%{type: :prev} = assigns) do
    pagination_link = get_pagination_link(assigns.path, assigns.current_page - 1)

    assigns = assign(assigns, :href, pagination_link)

    ~H"""
    <.link href={@href}>
      <button class={["btn bg-base-100", @class]} aria-label={Backpex.translate("Previous page")}>
        <Backpex.HTML.CoreComponents.icon name="hero-chevron-left" class="h-4 w-4" />
      </button>
    </.link>
    """
  end

  defp pagination_item(%{type: :next} = assigns) do
    pagination_link = get_pagination_link(assigns.path, assigns.current_page + 1)

    assigns = assign(assigns, :href, pagination_link)

    ~H"""
    <.link href={@href}>
      <button class={["btn bg-base-100", @class]} aria-label={Backpex.translate("Next page")}>
        <Backpex.HTML.CoreComponents.icon name="hero-chevron-right" class="h-4 w-4" />
      </button>
    </.link>
    """
  end

  defp pagination_item(%{type: :placeholder} = assigns) do
    ~H"""
    <button class={["btn bg-base-100", @class]} aria-disable="true">
      ...
    </button>
    """
  end

  defp get_pagination_link(path, page), do: String.replace(path, ":page", page |> Integer.to_string())

  @doc """
  Creates a list of pagination items based on the current page and the total number of pages. A maximum of five pages will be displayed.

  ### Example

      iex> Backpex.HTML.Resource.pagination_items(1, 1)
      [%{type: :number, number: 1}]

      iex> Backpex.HTML.Resource.pagination_items(1, 2)
      [%{type: :number, number: 1}, %{type: :number, number: 2}, %{type: :next, number: nil}]

      iex> Backpex.HTML.Resource.pagination_items(2, 2)
      [%{type: :prev, number: nil}, %{type: :number, number: 1}, %{type: :number, number: 2}]

      iex> Backpex.HTML.Resource.pagination_items(2, 8)
      [%{type: :prev, number: nil}, %{type: :number, number: 1}, %{type: :number, number: 2}, %{type: :number, number: 3}, %{type: :number, number: 4}, %{type: :placeholder, number: nil}, %{type: :number, number: 8}, %{type: :next, number: nil}]

      iex> Backpex.HTML.Resource.pagination_items(5, 10)
      [%{type: :prev, number: nil}, %{type: :number, number: 1}, %{type: :placeholder, number: nil}, %{type: :number, number: 4}, %{type: :number, number: 5}, %{type: :number, number: 6}, %{type: :placeholder, number: nil}, %{type: :number, number: 10}, %{type: :next, number: nil}]

      iex> Backpex.HTML.Resource.pagination_items(9, 10)
      [%{type: :prev, number: nil}, %{type: :number, number: 1}, %{type: :placeholder, number: nil}, %{type: :number, number: 7}, %{type: :number, number: 8}, %{type: :number, number: 9}, %{type: :number, number: 10}, %{type: :next, number: nil}]
  """
  def pagination_items(_current_page, total_pages) when total_pages <= 0, do: [%{type: :number, number: 1}]

  def pagination_items(current_page, total_pages) do
    Enum.reduce(1..total_pages, [], fn page, acc ->
      add_pagination_item(acc, current_page, total_pages, page)
    end)
    |> Enum.reverse()
    |> maybe_add_prev(current_page, total_pages)
    |> maybe_add_next(current_page, total_pages)
  end

  # Always display first and last page
  defp add_pagination_item(acc, _current_page, total_pages, page) when page == 1 or page == total_pages do
    [%{type: :number, number: page} | acc]
  end

  # Display page when current page and page are close to first page
  defp add_pagination_item(acc, current_page, _total_pages, page) when current_page < 4 and page < 5 do
    [%{type: :number, number: page} | acc]
  end

  # Display page when current page and page are close to last page
  defp add_pagination_item(acc, current_page, total_pages, page)
       when total_pages - current_page < 3 and total_pages - page < 4 do
    [%{type: :number, number: page} | acc]
  end

  # Display surrounding pages if current page and page are in the middle of all pages
  defp add_pagination_item(acc, current_page, total_pages, page)
       when total_pages - current_page >= 3 and current_page >= 4 and Kernel.abs(current_page - page) == 1 do
    [%{type: :number, number: page} | acc]
  end

  # Always display current page (page == current_page)
  defp add_pagination_item(acc, current_page, _total_pages, page) when page == current_page do
    [%{type: :number, number: page} | acc]
  end

  # Do not display consecutive placeholders
  defp add_pagination_item([%{type: :placeholder} | _rest] = acc, _current_page, _total_pages, _page) do
    acc
  end

  # Display placeholder for pages that are not shown
  defp add_pagination_item(acc, _current_page, _total_pages, _page) do
    [%{type: :placeholder, number: nil} | acc]
  end

  defp maybe_add_prev(pages, current_page, _total_pages) when current_page > 1 do
    [%{type: :prev, number: nil} | pages]
  end

  defp maybe_add_prev(pages, _current_page, _total_pages) do
    pages
  end

  defp maybe_add_next(pages, current_page, total_pages) when current_page < total_pages do
    pages
    |> Enum.reverse()
    |> Kernel.then(fn pages ->
      [%{type: :next, number: nil} | pages]
    end)
    |> Enum.reverse()
  end

  defp maybe_add_next(pages, _current_page, _total_pages) do
    pages
  end

  @doc """
  Renders a select per page button.
  """
  @doc type: :component

  attr :options, :list, required: true, doc: "A list of per page options."
  attr :query_options, :map, default: %{}, doc: "The query options."
  attr :class, :string, default: "", doc: "Extra class to be added to the select."

  def select_per_page(assigns) do
    form = to_form(%{}, as: :select_per_page)

    assigns =
      assigns
      |> assign(:form, form)
      |> assign(:selected, assigns.query_options.per_page)

    ~H"""
    <.form for={@form} class={@class} phx-change="select-page-size" phx-submit="select-page-size">
      <select name={@form[:value].name} class="select select-sm">
        {Phoenix.HTML.Form.options_for_select(@options, @selected)}
      </select>
    </.form>
    """
  end

  @doc """
  Renders a button group with create and resource action buttons.
  """
  @doc type: :component

  attr :socket, :any, required: true
  attr :live_resource, :any, required: true, doc: "module of the live resource"
  attr :params, :string, required: true, doc: "query parameters"
  attr :query_options, :map, default: %{}, doc: "query options"
  attr :resource_actions, :list, default: [], doc: "list of all resource actions provided by the resource configuration"
  attr :singular_name, :string, required: true, doc: "singular name of the resource"

  def resource_buttons(assigns) do
    ~H"""
    <div class="mb-4 flex space-x-2">
      <.link :if={@live_resource.can?(assigns, :new, nil)} patch={Router.get_path(@socket, @live_resource, @params, :new)}>
        <button class="btn btn-sm btn-outline btn-primary">
          {@create_button_label}
        </button>
      </.link>

      <.link
        :for={{key, action} <- resource_actions(assigns, @resource_actions)}
        patch={Router.get_path(@socket, @live_resource, @params, :resource_action, key, @query_options)}
      >
        <button class="btn btn-sm btn-outline btn-primary">
          {ResourceAction.name(action, :label)}
        </button>
      </.link>

      <div :if={display_divider?(assigns)} class="border-base-300 my-0.5 border-r-2 border-solid" />

      <button
        :for={{key, action} <- index_item_actions(@item_actions)}
        class="btn btn-sm btn-outline btn-primary"
        disabled={action_disabled?(assigns, key, @selected_items)}
        phx-click="item-action"
        phx-value-action-key={key}
      >
        {action.module.label(assigns, nil)}
      </button>
    </div>
    """
  end

  @doc """
  Renders the input fields for filters and search.
  """
  @doc type: :component

  attr :live_resource, :any, required: true, doc: "module of the live resource"

  attr :searchable_fields, :list,
    default: [],
    doc: "The fields that can be searched. Here only used to hide the component when empty."

  attr :full_text_search, :string, default: nil, doc: "full text search column name"
  attr :query_options, :map, default: %{}, doc: "query options"
  attr :search_placeholder, :string, required: true, doc: "placeholder for the search input"

  def resource_filters(assigns) do
    ~H"""
    <div class="mb-4 flex flex-wrap gap-4">
      <.metric_toggle {assigns} />
      <.index_search_form
        searchable_fields={@searchable_fields}
        full_text_search={@full_text_search}
        value={Map.get(@query_options, :search, "")}
        placeholder={@search_placeholder}
      />
      <.index_filter
        live_resource={@live_resource}
        filter_options={LiveResource.get_filter_options(@query_options)}
        filters={LiveResource.active_filters(assigns)}
      />
    </div>
    """
  end

  defp selected?(selected_items, item), do: Enum.member?(selected_items, item)

  defp active?(active_fields, name) do
    active_fields
    |> Keyword.get(name)
    |> Map.get(:active)
  end

  defp resource_actions(assigns, resource_actions) do
    Enum.filter(resource_actions, fn {key, _action} ->
      assigns.live_resource.can?(assigns, key, nil)
    end)
  end

  defp display_divider?(assigns) do
    index_item_actions = index_item_actions(assigns.item_actions)
    resource_actions = resource_actions(assigns, assigns.resource_actions)

    Enum.any?(index_item_actions) &&
      (Enum.any?(resource_actions) || assigns.live_resource.can?(assigns, :new, nil))
  end

  defp index_item_actions(item_actions) do
    Enum.filter(item_actions, fn {_key, action} ->
      action_on_index?(action)
    end)
  end

  defp row_item_actions(item_actions) do
    Enum.filter(item_actions, fn {_key, action} ->
      action_on_row?(action)
    end)
  end

  defp action_disabled?(assigns, action_key, items) do
    Enum.filter(items, fn item ->
      assigns.live_resource.can?(assigns, action_key, item)
    end)
    |> Enum.empty?()
  end

  defp action_on_row?(%{only: only}), do: :row in only
  defp action_on_row?(%{except: except}), do: :row not in except
  defp action_on_row?(_action), do: true

  defp action_on_index?(%{only: only}), do: :index in only
  defp action_on_index?(%{except: except}), do: :index not in except
  defp action_on_index?(_action), do: true

  @doc """
  Renders an info block to indicate that no items are found.
  """
  @doc type: :component

  attr :socket, :any, required: true
  attr :live_resource, :atom, required: true, doc: "live resource module"
  attr :params, :map, required: true, doc: "query params"
  attr :singular_name, :string, required: true, doc: "singular name of the resource"

  def empty_state(assigns) do
    assigns =
      assigns
      |> assign(:search_active?, get_in(assigns, [:query_options, :search]) not in [nil, ""])
      |> assign(:filter_active?, get_in(assigns, [:query_options, :filters]) != %{})
      |> assign(:title, Backpex.translate({"No %{resources} found", %{resources: assigns.plural_name}}))
      |> assign(:create_allowed, assigns.live_resource.can?(assigns, :new, nil))

    ~H"""
    <div class="flex justify-center py-16">
      <div class="flex flex-col justify-center">
        <div class="text-center">
          <.empty_state_content
            :if={@search_active?}
            title={@title}
            subtitle={Backpex.translate("Try a different search term.")}
          />
          <.empty_state_content
            :if={not @search_active? and @filter_active?}
            title={@title}
            subtitle={Backpex.translate("Try a different filter setting or clear all filters.")}
          />
          <.empty_state_content :if={not @search_active? and not @filter_active?} title={@title}>
            <.link :if={@create_allowed} patch={Router.get_path(@socket, @live_resource, @params, :new)}>
              <button class="btn btn-sm btn-outline btn-primary mt-6">
                {@create_button_label}
              </button>
            </.link>
          </.empty_state_content>
        </div>
      </div>
    </div>
    """
  end

  attr :title, :string, required: true, doc: "main title of the empty state info block"
  attr :subtitle, :string, default: nil, doc: "subtitle of the empty state info block"

  slot :inner_block

  defp empty_state_content(assigns) do
    ~H"""
    <Backpex.HTML.CoreComponents.icon name="hero-folder-plus" class="text-base-content/30 mb-1 inline-block h-12 w-12" />
    <p class="text-base-content text-lg font-bold">{@title}</p>
    <p :if={@subtitle} class="text-base-content/75">{@subtitle}</p>
    {render_slot(@inner_block)}
    """
  end

  @doc """
  Renders the main resource index content.
  """
  @doc type: :component

  attr :socket, :any, required: true
  attr :live_resource, :any, required: true, doc: "module of the live resource"
  attr :params, :string, required: true, doc: "query parameters"
  attr :query_options, :map, default: %{}, doc: "query options"
  attr :total_pages, :integer, default: 1, doc: "amount of total pages"

  attr :resource_actions, :list,
    default: [],
    doc: "list of all resource actions provided by the resource configuration"

  attr :singular_name, :string, required: true, doc: "singular name of the resource"

  attr :orderable_fields, :list, default: [], doc: "list of orderable fields."
  attr :items, :list, default: [], doc: "items that will be displayed in the table"

  attr :fields, :list,
    default: [],
    doc: "list of fields to be displayed in the table on index view"

  def resource_index_main(assigns)

  def resource_form_main(assigns)

  @doc """
  Renders a show card.
  """
  @doc type: :component

  attr :socket, :any, required: true
  attr :live_resource, :any, required: true, doc: "module of the live resource"
  attr :params, :string, required: true, doc: "query parameters"
  attr :item, :map, required: true, doc: "item that will be rendered on the card"
  attr :fields, :list, required: true, doc: "list of fields to be displayed on the card"

  def resource_show_main(assigns)

  @doc """
  Renders a show panel.
  """
  @doc type: :component

  attr :panel_fields, :list, required: true, doc: "list of fields to be rendered in the panel"
  attr :class, :string, default: "", doc: "extra class to be added"
  attr :label, :any, default: nil, doc: "optional label for the panel"

  def show_panel(assigns) do
    ~H"""
    <div class={@class}>
      <p :if={@label != nil} class="text-lg font-semibold">
        {@label}
      </p>

      <div class="card bg-base-100 mt-4">
        <div class="card-body p-0">
          <div class="flex flex-col sm:divide-base-200 sm:divide-y">
            <div :for={{name, %{label: label}} <- @panel_fields}>
              <.field_container>
                <:label>
                  <.input_label text={label} />
                </:label>
                <.resource_field name={name} {assigns} />
              </.field_container>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders an card for wrapping form fields. May be used to recreate the look of an Backpex edit view.

  ## Examples

      <.form :let={f} for={@form} phx-change="validate" phx-submit="submit">
        <.edit_card>
          <:panel label="Names">
            <.input field={f[:first_name]} type="text" />
            <.input field={f[:last_name]} type="text" />
          </:panel>

          <:actions>
            <button>Save</button>
          </:action>
        </.edit_card>
      </.form>
  """
  @doc type: :component

  slot :panel, doc: "a panel section" do
    attr :class, :string, doc: "optional class to be added to the wrapping panel element"
    attr :label, :string, doc: "optional label to be displayed as a headline for the panel"
  end

  slot :actions, doc: "actions like a save or cancel button"

  def edit_card(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-sm">
      <div class="card-body p-0">
        <%!-- Card Body --%>
        <div class="first:pt-3 last:pb-3">
          <fieldset :for={{panel, i} <- Enum.with_index(@panel)} class={Map.get(panel, :class)}>
            <div :if={panel[:label]}>
              <hr :if={i != 0} class="border-1 border-base-200 mb-8" />

              <legend class="mb-4 px-6 text-lg font-semibold">
                {panel[:label]}
              </legend>
            </div>
            {render_slot(panel)}
          </fieldset>
        </div>

        <%!-- Action Buttons --%>
        <div class="bg-base-200/50 rounded-b-box flex items-center justify-end space-x-4 px-6 py-3">
          {render_slot(@actions)}
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders the metrics area for the current resource.
  """
  @doc type: :component

  attr :metrics, :list, default: [], doc: "list of metrics to be displayed"

  def resource_metrics(assigns) do
    %{metric_visibility: metric_visibility, live_resource: live_resource} = assigns

    assigns =
      assigns
      |> assign(visible: Backpex.Metric.metrics_visible?(metric_visibility, live_resource))

    ~H"""
    <div :if={length(@metrics) > 0 and @visible} class="items-center gap-4 lg:flex">
      <%= for {_key, metric} <- @metrics do %>
        {component(
          &metric.module.render/1,
          [metric: metric],
          {__ENV__.module, __ENV__.function, __ENV__.file, __ENV__.line}
        )}
      <% end %>
    </div>
    """
  end

  defp metric_toggle(assigns) do
    visible = Backpex.Metric.metrics_visible?(assigns.metric_visibility, assigns.live_resource)

    form =
      %{"_resource" => assigns.live_resource, "_cookie_redirect_url" => assigns.current_url}
      |> to_form(as: :toggle_metrics)

    assigns =
      assigns
      |> assign(:visible, visible)
      |> assign(:form, form)

    ~H"""
    <div :if={length(@metrics) > 0}>
      <.form method="POST" for={@form} action={Router.cookie_path(@socket)}>
        <input type="hidden" name={@form[:_resource].name} value={@form[:_resource].value} />
        <input type="hidden" name={@form[:_cookie_redirect_url].name} value={@form[:_cookie_redirect_url].value} />
        <div id="toggle-metrics-button" phx-hook="BackpexTooltip" data-tooltip={Backpex.translate("Toggle metrics")}>
          <button
            type="submit"
            class={["btn btn-sm", @visible && "btn-primary", !@visible && "btn-neutral"]}
            aria-label={Backpex.translate("Toggle metrics")}
          >
            <Backpex.HTML.CoreComponents.icon name="hero-chart-bar-square" class="h-5 w-5" />
          </button>
        </div>
      </.form>
    </div>
    """
  end

  defp index_column_class(_assigns, %{index_column_class: class} = _field_options) when is_binary(class) do
    class
  end

  defp index_column_class(assigns, %{index_column_class: class} = _field_options) when is_function(class) do
    class.(assigns)
  end

  defp index_column_class(_assign, _field_options) do
    nil
  end

  defp align(field_options) do
    class =
      field_options
      |> Map.get(:align, :left)
      |> align_class()

    "flex #{class}"
  end

  defp index_row_class(assigns, item, selected, index) do
    base_class = if selected, do: "bg-base-200", else: "bg-base-100"
    extra_class = assigns.live_resource.index_row_class(assigns, item, selected, index)

    [base_class, extra_class]
  end

  defp sticky_col_class do
    [
      "sticky right-0",
      "after:[&[stuck]]:block after:absolute after:inset-y-0 after:left-0 after:hidden",
      "after:border-r after:border-base-200 after:shadow-[-1px_0_2px_0_rgba(0,0,0,0.05)]"
    ]
  end

  defp align_class(:left), do: "justify-start text-left"
  defp align_class(:right), do: "justify-end text-right"
  defp align_class(:center), do: "justify-center text-center"
  defp align_class(_alignment), do: "justify-start text-left"

  defp toggle_order_direction(:asc), do: :desc
  defp toggle_order_direction(:desc), do: :asc

  defp primary_value(item, live_resource) do
    item
    |> Map.get(live_resource.config(:primary_key))
  end
end
