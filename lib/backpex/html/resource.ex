defmodule Backpex.HTML.Resource do
  @moduledoc """
  Contains all Backpex resource components.
  """
  use BackpexWeb, :html

  import Phoenix.LiveView.TagEngine
  import Backpex.HTML.CoreComponents
  import Backpex.HTML.Form
  import Backpex.HTML.Layout

  alias Backpex.LiveResource
  alias Backpex.ResourceAction
  alias Backpex.Router

  require Backpex

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
    next_order_direction =
      cond do
        assigns.name != assigns.query_options.order_by -> :asc
        assigns.query_options.order_direction == :asc -> :desc
        true -> :asc
      end

    patch_link =
      Router.get_path(
        assigns.socket,
        assigns.live_resource,
        assigns.params,
        :index,
        Map.merge(assigns.query_options, %{order_direction: next_order_direction, order_by: assigns.name})
      )

    assigns =
      assigns
      |> assign(:next_order_direction, next_order_direction)
      |> assign(:patch_link, patch_link)

    ~H"""
    <.link class="flex items-center space-x-1" patch={@patch_link} replace>
      <p>{@label}</p>
      <%= if @name == @query_options.order_by do %>
        <.icon :if={@next_order_direction == :asc} name="hero-arrow-down-solid" class="size-4" />
        <.icon :if={@next_order_direction == :desc} name="hero-arrow-up-solid" class="size-4" />
      <% end %>
    </.link>
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
    %{name: name, item: item, live_resource: live_resource, fields: fields} = assigns

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
      |> assign(:readonly, Backpex.Field.readonly?(field_options, assigns))

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

  @doc false
  attr :live_resource, :any, default: nil, doc: "module of the live resource"
  attr :filter_options, :list, required: true, doc: "filter options"
  attr :filters, :list, required: true, doc: "list of active filters"

  def filter(assigns) do
    assigns =
      assigns
      |> assign(:filter_count, Enum.count(assigns.filter_options))
      |> assign(
        :filter_badges,
        for {key, value} <- assigns.filter_options do
          filter = Keyword.get(assigns.filters, String.to_existing_atom(key))
          label = Map.get(filter, :label, filter.module.label())

          %{
            key: key,
            value: value,
            filter: filter,
            label: label
          }
        end
      )

    ~H"""
    <.filter_dropdown :if={@filters != []} live_resource={@live_resource} filter_count={@filter_count}>
      <.filter_forms filters={@filters} filter_options={@filter_options} live_resource={@live_resource} {assigns} />
    </.filter_dropdown>
    <.filter_badge
      :for={badge <- @filter_badges}
      filter_name={badge.key}
      clear_event="clear-filter"
      label={badge.label}
      live_resource={@live_resource}
    >
      {component(
        &badge.filter.module.render/1,
        Map.merge(assigns, %{value: badge.value}),
        {__ENV__.module, __ENV__.function, __ENV__.file, __ENV__.line}
      )}
    </.filter_badge>
    """
  end

  @doc """
  Renders a dropdown button that typically contains filter forms for the resource index.

  It provides the main filter interface with a button that shows a funnel icon and a "Filters" label.
  When clicked, it opens a dropdown containing all available filter forms.
  The button displays a badge with the count of active filters when any filters are applied.

  ## Examples

      <.filter_dropdown filter_count={@filter_count}>
        <.form :let={f} for={@form} phx-change="change-filter" class="space-y-5">
          <.filter_form_field filter_name={:status} label="Status" show_clear_button={@filter_opts[:status]}>
            <.input type="select" prompt="Select status..." options={@status_options} />
          </.filter_form_field>
        </.form>
      </.filter_dropdown>
  """
  @doc type: :component

  attr :live_resource, :any, default: nil, doc: "live resource module"
  attr :filter_count, :integer, doc: "number of currently active filters (shows as badge when > 0)"

  slot :inner_block, required: true, doc: "filter forms content"

  def filter_dropdown(assigns) do
    ~H"""
    <div class="dropdown">
      <div class="indicator">
        <span :if={@filter_count > 0} class="indicator-item badge badge-sm badge-secondary rounded-selector">
          {@filter_count}
        </span>
        <label tabindex="0" class="btn btn-sm btn-outline border-base-content/20 border-(length:--border)">
          <Backpex.HTML.CoreComponents.icon name="hero-funnel-solid" class="size-5 text-primary mr-2" />
          {Backpex.__("Filters", @live_resource)}
        </label>
      </div>
      <div
        role="button"
        tabindex="0"
        class="dropdown-content z-[1] menu bg-base-100 rounded-box outline-black/5 p-4 shadow outline-[length:var(--border)]"
      >
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  @doc """
  Renders an active filter badge with its value and a clear button.

  This component displays applied filters as visual badges that show both the filter label
  and its current value. Each badge includes a clear button (×) that allows users to
  remove individual filters.

  ## Examples

      <.filter_badge
        filter_name="status"
        label="Status"
        live_resource={MyApp.UserLive}
      >
        Active
      </.filter_badge>
  """
  @doc type: :component

  attr :live_resource, :any, default: nil, doc: "live resource module"
  attr :clear_event, :string, default: "clear-filter", doc: "event triggered when the clear button is clicked"
  attr :filter_name, :string, required: true, doc: "unique identifier for the filter being displayed"
  attr :label, :string, required: true, doc: "human-readable filter name displayed on the badge"

  slot :inner_block,
    required: true,
    doc: "rendered filter value content (typically from filter module's render/1 function)"

  def filter_badge(assigns) do
    ~H"""
    <div class="indicator">
      <div class="join">
        <div class="btn btn-sm join-item bg-base-300 border-base-content/20 pointer-events-none font-semibold">
          {@label}
        </div>
        <div class="btn btn-sm btn-outline join-item border-base-content/20 pointer-events-none border-l-transparent">
          {render_slot(@inner_block)}
        </div>
      </div>
      <button
        type="button"
        phx-click={@clear_event}
        phx-value-field={@filter_name}
        class="indicator-item bg-base-300 rounded-selector grid cursor-pointer place-items-center p-1 shadow-sm transition duration-75 hover:text-secondary hover:scale-110"
        aria-label={Backpex.__({"Clear %{name} filter", %{name: @label}}, @live_resource)}
      >
        <.icon name="hero-x-mark" class="size-3" />
      </button>
    </div>
    """
  end

  @doc false
  attr :live_resource, :any, default: nil, doc: "live resource module"
  attr :filters, :list, required: true, doc: "list of active filters"
  attr :filter_options, :list, required: true, doc: "filter options"

  def filter_forms(assigns) do
    assigns =
      assigns
      |> assign(:form, to_form(%{}, as: :filters))
      |> assign(
        :filter_fields,
        for {field, filter} <- assigns.filters do
          label = Map.get(filter, :label, filter.module.label())
          presets = Map.get(filter, :presets, [])
          value = Map.get(assigns.filter_options, Atom.to_string(field), nil)

          %{
            field: field,
            filter: filter,
            label: label,
            presets: presets,
            value: value
          }
        end
      )

    ~H"""
    <.form :let={f} for={@form} phx-change="change-filter" phx-submit="change-filter" class="space-y-5">
      <div :for={field_data <- @filter_fields}>
        <.filter_form_field
          live_resource={@live_resource}
          filter_name={field_data.field}
          label={field_data.label}
          show_clear_button={field_data.value != nil}
        >
          {component(
            &field_data.filter.module.render_form/1,
            Map.merge(assigns, %{field: field_data.field, value: field_data.value, form: f, live_resource: @live_resource}),
            {__ENV__.module, __ENV__.function, __ENV__.file, __ENV__.line}
          )}
          <:presets :if={field_data.presets != []}>
            <.filter_presets presets={field_data.presets} filter_name={field_data.field} />
          </:presets>
        </.filter_form_field>
      </div>
    </.form>
    """
  end

  @doc """
  Renders a filter field container with label, form inputs, and optional clear button.
  Providing a structured layout for individual filter controls within the filter menu.

  Typically used within `.filter_forms/1` to render each individual filter in the filter dropdown.
  The form inputs are provided via the inner_block slot, while preset buttons are provided via
  the presets slot.

  ## Examples

      <.filter_form_field
        filter_name={:status}
        label="Status"
        show_clear_button={@has_status_filter}
      >
        <.input type="select" field={@form[:status]} options={@status_options} />
        <:presets>
          <.filter_presets presets={[{"Active", "active"}, {"Inactive", "inactive"}]} />
        </:presets>
      </.filter_form_field>
  """
  @doc type: :component

  attr :live_resource, :any, default: nil, doc: "live resource module"
  attr :clear_event, :string, default: "clear-filter", doc: "event name triggered when clearing the filter"
  attr :filter_name, :string, required: true, doc: "unique identifier for the filter field"
  attr :label, :string, required: true, doc: "human-readable label displayed above the filter"

  attr :show_clear_button, :boolean,
    required: true,
    doc: "whether to show the clear button (typically when filter has a value)"

  slot :inner_block, required: true, doc: "filter form inputs (selects, text inputs, etc.)"
  slot :presets, doc: "optional preset buttons for common filter values"

  def filter_form_field(assigns) do
    ~H"""
    <div class="flex space-x-2">
      <p class="text-sm font-medium">{@label}</p>
      <.filter_clear_button
        :if={@show_clear_button}
        clear_event={@clear_event}
        live_resource={@live_resource}
        filter_name={@filter_name}
      />
    </div>
    <div class="flex space-x-4">
      <div class="w-[240px]">
        {render_slot(@inner_block)}
      </div>
      {render_slot(@presets)}
    </div>
    """
  end

  @doc false
  attr :select_filter_preset_event, :string,
    default: "filter-preset-selected",
    doc: "event name for selecting filter presets"

  attr :presets, :list, required: true, doc: "list of presets"
  attr :filter_name, :string, required: true, doc: "name of the filter"

  def filter_presets(assigns) do
    ~H"""
    <div class="min-w-[80px] mt-2">
      <div
        :for={{preset, index} <- Enum.with_index(@presets)}
        phx-click={@select_filter_preset_event}
        phx-value-field={@filter_name}
        phx-value-preset-index={index}
        class="text-primary mb-1 cursor-pointer truncate text-xs font-medium hover:underline"
      >
        {preset.label}
      </div>
    </div>
    """
  end

  @doc false
  attr :clear_event, :string, default: "clear-filter", doc: "event name for clearing the filter"
  attr :live_resource, :any, required: true, doc: "live resource module"
  attr :filter_name, :string, required: true, doc: "name of the filter"

  def filter_clear_button(assigns) do
    ~H"""
    <button
      type="button"
      phx-click={@clear_event}
      phx-value-field={@filter_name}
      class="text-primary cursor-pointer text-xs font-medium hover:underline"
    >
      {Backpex.__("clear", @live_resource)}
    </button>
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
          {Backpex.__("Toggle columns", @live_resource)}
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
            {Backpex.__("Save", @live_resource)}
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
  attr :live_resource, :atom, default: nil, doc: "the live resource module"

  def pagination_info(assigns) do
    %{query_options: %{page: page, per_page: per_page}} = assigns

    from = (page - 1) * per_page + 1
    to = min(page * per_page, assigns.total)

    from_to_string = Backpex.__({"Items %{from} to %{to}", %{from: from, to: to}}, assigns.live_resource)
    total_string = Backpex.__({"(%{count} total)", %{count: assigns.total}}, assigns.live_resource)

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
  attr :next_page_label, :string, default: "Next page"
  attr :previous_page_label, :string, default: "Previous page"

  def pagination(assigns) do
    assigns = assign(assigns, :pagination_items, pagination_items(assigns.current_page, assigns.total_pages))

    ~H"""
    <div class="join">
      <.pagination_item
        :for={%{type: type, number: number} <- @pagination_items}
        class="join-item"
        type={type}
        number={number}
        current_page={@current_page}
        path={@path}
        next_page_label={@next_page_label}
        previous_page_label={@previous_page_label}
      />
    </div>
    """
  end

  attr :path, :string, required: true
  attr :current_page, :integer, required: true
  attr :type, :atom, required: true
  attr :number, :integer, default: nil, required: false
  attr :class, :string, default: nil
  attr :next_page_label, :string, default: "Next page"
  attr :previous_page_label, :string, default: "Previous page"

  defp pagination_item(%{type: :number} = assigns) do
    pagination_link = get_pagination_link(assigns.path, assigns.number)

    assigns =
      assigns
      |> assign(:btn_class, pagination_btn_class())
      |> assign(:link, pagination_link)

    ~H"""
    <.link patch={@link} class={[@btn_class, @current_page == @number && "bg-base-300", @class]}>
      {Integer.to_string(@number)}
    </.link>
    """
  end

  defp pagination_item(%{type: :prev} = assigns) do
    pagination_link = get_pagination_link(assigns.path, assigns.current_page - 1)

    assigns =
      assigns
      |> assign(:btn_class, pagination_btn_class())
      |> assign(:link, pagination_link)

    ~H"""
    <.link patch={@link} class={[@btn_class, @class]} aria-label={@previous_page_label}>
      <Backpex.HTML.CoreComponents.icon name="hero-chevron-left" class="size-4" />
    </.link>
    """
  end

  defp pagination_item(%{type: :next} = assigns) do
    pagination_link = get_pagination_link(assigns.path, assigns.current_page + 1)

    assigns =
      assigns
      |> assign(:btn_class, pagination_btn_class())
      |> assign(:link, pagination_link)

    ~H"""
    <.link patch={@link} class={[@btn_class, @class]} aria-label={@next_page_label}>
      <Backpex.HTML.CoreComponents.icon name="hero-chevron-right" class="size-4" />
    </.link>
    """
  end

  defp pagination_item(%{type: :placeholder} = assigns) do
    assigns = assign(assigns, :btn_class, pagination_btn_class())

    ~H"""
    <button class={[@btn_class, @class]} aria-disable="true">
      ...
    </button>
    """
  end

  defp pagination_btn_class, do: ["btn btn-sm bg-base-100 hover:bg-[var(--btn-border)]"]

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

  attr :query_options, :map, default: %{}, doc: "query options"
  attr :search_placeholder, :string, required: true, doc: "placeholder for the search input"

  def resource_filters(assigns) do
    ~H"""
    <div class="mb-4 flex flex-wrap gap-4">
      <.metric_toggle {assigns} />
      <.index_search_form
        searchable_fields={@searchable_fields}
        full_text_search={@live_resource.config(:full_text_search)}
        value={Map.get(@query_options, :search, "")}
        placeholder={@search_placeholder}
      />
      <.filter
        :if={LiveResource.active_filters(assigns) != []}
        live_resource={@live_resource}
        filter_options={LiveResource.get_filter_options(@query_options)}
        filters={LiveResource.active_filters(assigns)}
        {assigns}
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
    plural_name = assigns.live_resource.plural_name()

    assigns =
      assigns
      |> assign(:search_active?, get_in(assigns, [:query_options, :search]) not in [nil, ""])
      |> assign(:filter_active?, get_in(assigns, [:query_options, :filters]) != %{})
      |> assign(:title, Backpex.__({"No %{resources} found", %{resources: plural_name}}, assigns.live_resource))
      |> assign(:create_allowed, assigns.live_resource.can?(assigns, :new, nil))

    ~H"""
    <div class="flex justify-center py-16">
      <div class="flex flex-col justify-center">
        <div class="text-center">
          <.empty_state_content
            :if={@search_active?}
            title={@title}
            subtitle={Backpex.__("Try a different search term.", @live_resource)}
          />
          <.empty_state_content
            :if={not @search_active? and @filter_active?}
            title={@title}
            subtitle={Backpex.__("Try a different filter setting or clear all filters.", @live_resource)}
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

      <div class="card bg-base-100 mt-4 shadow-sm">
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
        <div
          id="toggle-metrics-button"
          phx-hook="BackpexTooltip"
          data-tooltip={Backpex.__("Toggle metrics", @live_resource)}
        >
          <button
            type="submit"
            class={["btn btn-sm", @visible && "btn-active"]}
            aria-label={Backpex.__("Toggle metrics", @live_resource)}
          >
            <Backpex.HTML.CoreComponents.icon name="hero-chart-bar-square" class="size-6" />
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
      "[&[stuck]]:after:block after:absolute after:inset-y-0 after:left-0 after:hidden",
      "after:border-r after:border-base-200 after:shadow-[-1px_0_2px_0_rgba(0,0,0,0.05)]"
    ]
  end

  defp align_class(:left), do: "justify-start text-left"
  defp align_class(:right), do: "justify-end text-right"
  defp align_class(:center), do: "justify-center text-center"
  defp align_class(_alignment), do: "justify-start text-left"
end
