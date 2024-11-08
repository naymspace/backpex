defmodule Backpex.LiveResource do
  @moduledoc ~S'''
  A LiveResource makes it easy to manage existing resources in your application. It provides extensive configuration options in order to meet everyone's needs. In connection with `Backpex.Components` you can build an individual admin dashboard on top of your application in minutes.

  > #### `use Backpex.LiveResource` {: .info}
  >
  > When you `use Backpex.LiveResource`, the `Backpex.LiveResource` module will set `@behavior Backpex.LiveResource`. Additionally it will create a LiveView based on the given configuration in order to create fully functional index, show, new and edit views for a resource. It will also insert fallback functions that can be overridden.
  '''

  use Phoenix.LiveView
  import Backpex.HTML.Resource
  alias Backpex.Adapters.Ecto, as: EctoAdapter
  alias Backpex.Resource
  alias Backpex.ResourceAction
  alias Backpex.Router

  @empty_filter_key :empty_filter

  @permitted_order_directions ~w(asc desc)a

  @options_schema [
    adapter: [
      doc: "The data layer adapter to use.",
      type: :atom,
      default: Backpex.Adapters.Ecto
    ],
    adapter_config: [
      doc: "The configuration for the data layer. See corresponding adapter for possible configuration values.",
      type: :keyword_list,
      required: true
    ],
    primary_key: [
      doc: "The primary key used for identifying items.",
      type: :atom,
      default: :id
    ],
    layout: [
      doc: "Layout to be used by the LiveResource.",
      type: :mod_arg,
      required: true
    ],
    pubsub: [
      doc: "PubSub configuration.",
      type: :keyword_list,
      required: true,
      keys: [
        name: [
          doc: "PubSub name of the project.",
          required: true,
          type: :atom
        ],
        event_prefix: [
          doc:
            "The event prefix for Pubsub, to differentiate between events of different resources when subscribed to multiple resources.",
          required: true,
          type: :string
        ],
        topic: [
          doc: "The topic for PubSub.",
          required: true,
          type: :string
        ]
      ]
    ],
    per_page_options: [
      doc: "The page size numbers you can choose from.",
      type: {:list, :integer},
      default: [15, 50, 100]
    ],
    per_page_default: [
      doc: "The default page size number.",
      type: :integer,
      default: 15
    ],
    init_order: [
      doc: "Order that will be used when no other order options are given.",
      type: {
        :or,
        [
          {:fun, 1},
          map: [
            by: [
              doc: "The column used for ordering.",
              type: :atom
            ],
            direction: [
              doc: "The order direction",
              type: :atom
            ]
          ]
        ]
      },
      default: Macro.escape(%{by: :id, direction: :asc})
    ],
    fluid?: [
      type: :boolean,
      default: false
    ],
    full_text_search: [
      type: :atom,
      default: nil
    ]
  ]

  @doc """
  A list of [resource_actions](Backpex.ResourceAction.html) that may be performed on the given resource.
  """
  @callback resource_actions() :: list()

  @doc """
  A list of [item_actions](Backpex.ItemAction.html) that may be performed on (selected) items.
  """
  @callback item_actions(default_actions :: list(map())) :: list()

  @doc """
  A list of panels to group certain fields together.
  """
  @callback panels() :: list()

  @doc """
  A list of fields defining your resource. See `Backpex.Field`.
  """
  @callback fields() :: list()

  @doc """
  The singular name of the resource used for translations and titles.
  """
  @callback singular_name() :: binary()

  @doc """
  The plural name of the resource used for translations and titles.
  """
  @callback plural_name() :: binary()

  @doc """
  Replaces the default placeholder for the index search.
  """
  @callback search_placeholder() :: binary()

  @doc """
  An extra class to be added to table rows on the index view.
  """
  @callback index_row_class(assigns :: map(), item :: map(), selected :: boolean(), index :: integer()) ::
              binary() | nil

  @doc """
  The function that can be used to restrict access to certain actions. It will be called before performing
  an action and aborts when the function returns `false`.
  """
  @callback can?(assigns :: map(), action :: atom(), item :: map() | nil) :: boolean()

  @doc """
  The function that can be used to inject an ecto query. The query will be used when resources are being fetched. This happens on `index`, `edit`
  and `show` view. In most cases this function will be used to filter items on `index` view based on certain criteria, but it may also be used
  to join other tables on `edit` or `show` view.

  The function has to return an `Ecto.Query`. It is recommended to build your `item_query` on top of the incoming query. Otherwise you will likely get binding errors.
  """
  @callback item_query(query :: Ecto.Query.t(), live_action :: atom(), assigns :: map()) :: Ecto.Query.t()

  @doc """
  The function that can be used to add content to certain positions on Backpex views. It may also be used to overwrite content.

  The following actions are supported: `:index`, `:show`

  The following positions are supported for the `:index` action: `:page_title`, `:actions`, `:filters`, `:metrics` and `:main`.
  The following positions are supported for the `:show` action: `:page_title` and `:main`.

  In addition to this, content can be inserted between the main positions via the following extra spots: `:before_page_title`, `:before_actions`, `:before_filters`, `:before_metrics` and `:before_main`.
  """
  @callback render_resource_slot(assigns :: map(), action :: atom(), position :: atom()) ::
              %Phoenix.LiveView.Rendered{}

  @doc """
  A optional keyword list of [filters](Backpex.Filter.html) to be used on the index view.
  """
  @callback filters() :: keyword()

  @doc """
  A optional keyword list of [filters](Backpex.Filter.html) to be used on the index view.
  """
  @callback filters(assigns :: map()) :: keyword()

  @doc """
  A list of metrics shown on the index view of your resource.
  """
  @callback metrics() :: keyword()

  @doc """
  This function is executed when an item has been created.
  """
  @callback on_item_created(socket :: Phoenix.LiveView.Socket.t(), item :: map()) ::
              Phoenix.LiveView.Socket.t()

  @doc """
  This function is executed when an item has been updated.
  """
  @callback on_item_updated(socket :: Phoenix.LiveView.Socket.t(), item :: map()) ::
              Phoenix.LiveView.Socket.t()

  @doc """
  This function is executed when an item has been deleted.
  """
  @callback on_item_deleted(socket :: Phoenix.LiveView.Socket.t(), item :: map()) ::
              Phoenix.LiveView.Socket.t()

  @doc """
  This function navigates to the specified path when an item has been created or updated. Defaults to the previous resource path (index or edit).
  """
  @callback return_to(socket :: Phoenix.LiveView.Socket.t(), assigns :: map(), action :: atom(), item :: map()) ::
              binary()

  @doc """
  Customizes the label of the button for creating a new item. Defaults to "New %{resource}".
  """
  @callback create_button_label() :: binary()

  @doc """
  Customizes the message in the flash message when a resource has been created successfully. Defaults to "New %{resource} has been created successfully".
  """
  @callback resource_created_message() :: binary()

  @doc """
  Returns the schema of the live resource.
  """
  @callback schema() :: module()

  @doc """
  Uses LiveResource in the current module to make it a LiveResource.

      use Backpex.LiveResource,
        adapter_config: [
          schema: MyApp.User,
          repo: MyApp.Repo,
          update_changeset: &MyApp.User.update_changeset/3,
          create_changeset: &MyApp.User.create_changeset/3
        ],
        layout: {MyAppWeb.LayoutView, :admin}
        # ...

  ## Options

  #{NimbleOptions.docs(@options_schema)}
  """
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts, options_schema: @options_schema] do
      @before_compile Backpex.LiveResource
      @behaviour Backpex.LiveResource

      @resource_opts NimbleOptions.validate!(opts, options_schema)

      @resource_opts[:adapter].validate_config!(@resource_opts[:adapter_config])

      use BackpexWeb, :html
      use Phoenix.LiveView, layout: @resource_opts[:layout]

      import Backpex.LiveResource
      import Phoenix.LiveView.Helpers
      import Ecto.Query

      alias Backpex.LiveResource

      def config(key) do
        Keyword.fetch!(@resource_opts, key)
      end

      @impl Phoenix.LiveView
      def mount(params, session, socket) do
        LiveResource.mount(params, session, socket)
      end

      @impl Phoenix.LiveView
      def handle_params(params, url, socket) do
        LiveResource.handle_params(params, url, socket)
      end

      @impl Phoenix.LiveView
      def handle_event(event, params, socket) do
        LiveResource.handle_event(event, params, socket)
      end

      @impl Phoenix.LiveView
      def handle_info(msg, socket) do
        LiveResource.handle_info(msg, socket)
      end

      @impl Phoenix.LiveView
      def render(%{live_action: action} = assigns) when action in [:show, :show_edit] do
        resource_show(assigns)
      end

      @impl Phoenix.LiveView
      def render(%{live_action: action} = assigns) when action in [:new, :edit] do
        resource_form(assigns)
      end

      @impl Phoenix.LiveView
      def render(assigns) do
        resource_index(assigns)
      end

      @impl Backpex.LiveResource
      def can?(_assigns, _action, _item), do: true

      @impl Backpex.LiveResource
      def index_row_class(assigns, item, selected, index), do: nil

      @impl Backpex.LiveResource
      def fields, do: []

      @impl Backpex.LiveResource
      def filters, do: []

      @impl Backpex.LiveResource
      def filters(_assigns), do: filters()

      @impl Backpex.LiveResource
      def resource_actions, do: []

      @impl Backpex.LiveResource
      def item_actions(default_actions), do: default_actions

      @impl Backpex.LiveResource
      def create_button_label, do: Backpex.translate({"New %{resource}", %{resource: singular_name()}})

      @impl Backpex.LiveResource
      def schema, do: @resource_opts[:adapter_config][:schema]

      @impl Backpex.LiveResource
      def resource_created_message,
        do: Backpex.translate({"New %{resource} has been created successfully.", %{resource: singular_name()}})

      defoverridable can?: 3,
                     fields: 0,
                     filters: 0,
                     filters: 1,
                     resource_actions: 0,
                     item_actions: 1,
                     index_row_class: 4,
                     create_button_label: 0,
                     resource_created_message: 0
    end
  end

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defmacro __before_compile__(_env) do
    quote do
      import Backpex.HTML.Layout
      import Backpex.HTML.Resource
      alias Backpex.Router

      @impl Backpex.LiveResource
      def panels, do: []

      @impl Backpex.LiveResource
      def metrics, do: []

      @impl Backpex.LiveResource
      def search_placeholder, do: Backpex.translate("Search")

      @impl Backpex.LiveResource
      def item_query(query, _live_action, _assigns), do: query

      @impl Backpex.LiveResource
      def on_item_created(socket, _item), do: socket

      @impl Backpex.LiveResource
      def on_item_updated(socket, _item), do: socket

      @impl Backpex.LiveResource
      def on_item_deleted(socket, _item), do: socket

      @impl Backpex.LiveResource
      def return_to(socket, assigns, _action, _item) do
        Map.get(assigns, :return_to, Router.get_path(socket, assigns.live_resource, %{}, :index))
      end

      @impl Backpex.LiveResource
      def render_resource_slot(var!(assigns), :index, :page_title) do
        ~H"""
        <.main_title class="flex items-center justify-between">
          <%= @plural_name %>
        </.main_title>
        """
      end

      @impl Backpex.LiveResource
      def render_resource_slot(var!(assigns), :index, :actions) do
        ~H"""
        <.resource_buttons {assigns} />
        """
      end

      @impl Backpex.LiveResource
      def render_resource_slot(var!(assigns), :index, :filters) do
        ~H"""
        <.resource_filters {assigns} />
        """
      end

      @impl Backpex.LiveResource
      def render_resource_slot(var!(assigns), :index, :metrics) do
        ~H"""
        <.resource_metrics {assigns} />
        """
      end

      @impl Backpex.LiveResource
      def render_resource_slot(var!(assigns), :index, :main) do
        ~H"""
        <.resource_index_main {assigns} />
        """
      end

      @impl Backpex.LiveResource
      def render_resource_slot(var!(assigns), :show, :page_title) do
        ~H"""
        <.main_title class="flex items-center justify-between">
          <%= @singular_name %>
          <.link
            :if={@live_resource.can?(assigns, :edit, @item)}
            class="tooltip hover:z-30"
            data-tip={Backpex.translate("Edit")}
            aria-label={Backpex.translate("Edit")}
            patch={Router.get_path(@socket, @live_resource, @params, :edit, @item)}
          >
            <Backpex.HTML.CoreComponents.icon
              name="hero-pencil-square"
              class="h-6 w-6 cursor-pointer transition duration-75 hover:scale-110 hover:text-primary"
            />
          </.link>
        </.main_title>
        """
      end

      @impl Backpex.LiveResource
      def render_resource_slot(var!(assigns), :show, :main) do
        ~H"""
        <.resource_show_main {assigns} />
        """
      end

      @impl Backpex.LiveResource
      def render_resource_slot(var!(assigns), :edit, :page_title) do
        ~H"""
        <.main_title class="mb-4">
          <%= Backpex.translate({"Edit %{resource}", %{resource: @singular_name}}) %>
        </.main_title>
        """
      end

      @impl Backpex.LiveResource
      def render_resource_slot(var!(assigns), :new, :page_title) do
        ~H"""
        <.main_title class="mb-4">
          <%= @create_button_label %>
        </.main_title>
        """
      end

      @impl Backpex.LiveResource
      def render_resource_slot(var!(assigns), :edit, :main) do
        ~H"""
        <.resource_form_main {assigns} />
        """
      end

      @impl Backpex.LiveResource
      def render_resource_slot(var!(assigns), :new, :main) do
        ~H"""
        <.resource_form_main {assigns} />
        """
      end

      @impl Backpex.LiveResource
      def render_resource_slot(var!(assigns), _action, _position), do: ~H""
    end
  end

  @impl Phoenix.LiveView
  def mount(params, session, socket) do
    live_resource = socket.view
    pubsub = live_resource.config(:pubsub)
    subscribe_to_topic(socket, pubsub)

    # TODO: move these "config assigns" (and other global assigns) to where they are needed
    adapter_config = live_resource.config(:adapter_config)
    fluid? = live_resource.config(:fluid?)
    full_text_search = live_resource.config(:full_text_search)

    socket =
      socket
      |> assign(:live_resource, live_resource)
      |> assign(:schema, adapter_config[:schema])
      |> assign(:repo, adapter_config[:repo])
      |> assign(:singular_name, live_resource.singular_name())
      |> assign(:plural_name, live_resource.plural_name())
      |> assign(:create_button_label, live_resource.create_button_label())
      |> assign(:resource_created_message, live_resource.resource_created_message())
      |> assign(:search_placeholder, live_resource.search_placeholder())
      |> assign(:panels, live_resource.panels())
      |> assign(:fluid?, fluid?)
      |> assign(:full_text_search, full_text_search)
      |> assign_active_fields(session)
      |> assign_metrics_visibility(session)
      |> assign_filters_changed_status(params)

    {:ok, socket}
  end

  defp assign_active_fields(socket, session) do
    fields =
      socket.assigns.live_resource.fields()
      |> filtered_fields_by_action(socket.assigns, :index)

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

  defp field_active?(name, saved_fields) do
    case Map.get(saved_fields, Atom.to_string(name)) do
      "true" ->
        true

      "false" ->
        false

      _other ->
        true
    end
  end

  def assign_items(socket) do
    %{
      live_resource: live_resource,
      fields: fields
    } = socket.assigns

    criteria = build_criteria(socket.assigns)
    items = Resource.list(fields, socket.assigns, live_resource, criteria)

    assign(socket, :items, items)
  end

  defp maybe_assign_metrics(socket) do
    %{
      assigns:
        %{
          repo: repo,
          schema: schema,
          live_action: live_action,
          live_resource: live_resource,
          fields: fields,
          query_options: query_options,
          metric_visibility: metric_visibility
        } = assigns
    } = socket

    filters = active_filters(assigns)

    metrics =
      socket.assigns.live_resource.metrics()
      |> Enum.map(fn {key, metric} ->
        query =
          EctoAdapter.list_query(
            assigns,
            &socket.assigns.live_resource.item_query(&1, live_action, assigns),
            fields,
            search: search_options(query_options, fields, schema),
            filters: filter_options(query_options, filters)
          )

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

  @impl Phoenix.LiveView
  def handle_params(params, _url, socket) do
    socket =
      socket
      |> assign(:params, params)
      |> apply_item_actions(socket.assigns.live_action)
      |> apply_action(socket.assigns.live_action)

    {:noreply, socket}
  end

  def apply_action(socket, :index) do
    socket
    |> assign(:page_title, socket.assigns.plural_name)
    |> apply_index()
    |> assign(:item, nil)
  end

  def apply_action(socket, :edit) do
    %{
      live_resource: live_resource,
      singular_name: singular_name
    } = socket.assigns

    fields = live_resource.fields |> filtered_fields_by_action(socket.assigns, :edit)
    primary_value = URI.decode(socket.assigns.params["backpex_id"])
    item = Resource.get!(primary_value, socket.assigns, live_resource)

    unless live_resource.can?(socket.assigns, :edit, item), do: raise(Backpex.ForbiddenError)

    socket
    |> assign(:fields, fields)
    |> assign(:changeset_function, live_resource.config(:adapter_config)[:update_changeset])
    |> assign(:page_title, Backpex.translate({"Edit %{resource}", %{resource: singular_name}}))
    |> assign(:item, item)
    |> assign_changeset(fields)
  end

  def apply_action(socket, :show) do
    %{
      live_resource: live_resource,
      singular_name: singular_name
    } = socket.assigns

    fields = live_resource.fields() |> filtered_fields_by_action(socket.assigns, :show)
    primary_value = URI.decode(socket.assigns.params["backpex_id"])
    item = Resource.get!(primary_value, socket.assigns, live_resource)

    unless live_resource.can?(socket.assigns, :show, item), do: raise(Backpex.ForbiddenError)

    socket
    |> assign(:page_title, singular_name)
    |> assign(:fields, fields)
    |> assign(:item, item)
    |> apply_show_return_to(item)
  end

  def apply_action(socket, :new) do
    %{
      live_resource: live_resource,
      schema: schema,
      create_button_label: create_button_label
    } = socket.assigns

    unless live_resource.can?(socket.assigns, :new, nil), do: raise(Backpex.ForbiddenError)

    fields = live_resource.fields() |> filtered_fields_by_action(socket.assigns, :new)
    empty_item = schema.__struct__()

    socket
    |> assign(:changeset_function, live_resource.config(:adapter_config)[:create_changeset])
    |> assign(:page_title, create_button_label)
    |> assign(:fields, fields)
    |> assign(:item, empty_item)
    |> assign_changeset(fields)
  end

  def apply_action(socket, :resource_action) do
    %{live_resource: live_resource} = socket.assigns

    id =
      socket.assigns.params["backpex_id"]
      |> URI.decode()
      |> String.to_existing_atom()

    action = live_resource.resource_actions()[id]

    unless live_resource.can?(socket.assigns, id, nil), do: raise(Backpex.ForbiddenError)

    socket
    |> assign(:page_title, ResourceAction.name(action, :title))
    |> assign(:resource_action, action)
    |> assign(:resource_action_id, id)
    |> assign(:item, action.module.init_change(socket.assigns))
    |> apply_index()
    |> assign(:changeset_function, &action.module.changeset/3)
    |> assign_changeset(action.module.fields())
  end

  def apply_item_actions(socket, action) when action in [:index, :resource_action] do
    item_actions = socket.assigns.live_resource.item_actions(default_item_actions())
    assign(socket, :item_actions, item_actions)
  end

  def apply_item_actions(socket, _action), do: socket

  defp apply_index_return_to(socket) do
    %{live_resource: live_resource, params: params, query_options: query_options} = socket.assigns

    socket
    |> assign(
      :return_to,
      Router.get_path(socket, live_resource, params, :index, query_options)
    )
  end

  defp apply_show_return_to(socket, item) do
    %{live_resource: live_resource, params: params} = socket.assigns

    socket
    |> assign(:return_to, Router.get_path(socket, live_resource, params, :show, item))
  end

  defp apply_index(socket) do
    %{
      live_resource: live_resource,
      schema: schema,
      params: params
    } = socket.assigns

    unless live_resource.can?(socket.assigns, :index, nil), do: raise(Backpex.ForbiddenError)

    fields = live_resource.fields() |> filtered_fields_by_action(socket.assigns, :index)

    per_page_options = live_resource.config(:per_page_options)
    per_page_default = live_resource.config(:per_page_default)
    init_order = live_resource.config(:init_order)

    filters = active_filters(socket.assigns)
    valid_filter_params = get_valid_filters_from_params(params, filters, @empty_filter_key)

    count_criteria = [
      search: search_options(params, fields, schema),
      filters: filter_options(valid_filter_params, filters)
    ]

    item_count = Resource.count(fields, socket.assigns, live_resource, count_criteria)

    per_page =
      params
      |> parse_integer("per_page", per_page_default)
      |> value_in_permitted_or_default(per_page_options, per_page_default)

    total_pages = calculate_total_pages(item_count, per_page)
    page = params |> parse_integer("page", 1) |> validate_page(total_pages)

    page_options = %{page: page, per_page: per_page}

    order_options = order_options_by_params(params, fields, init_order, socket.assigns, @permitted_order_directions)

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
    |> assign(:orderable_fields, orderable_fields(fields))
    |> assign(:searchable_fields, searchable_fields(fields))
    |> assign(:resource_actions, live_resource.resource_actions())
    |> assign(:action_to_confirm, nil)
    |> assign(:selected_items, [])
    |> assign(:select_all, false)
    |> assign(:fields, fields)
    |> assign(:changeset_function, live_resource.config(:adapter_config)[:update_changeset])
    |> maybe_redirect_to_default_filters()
    |> assign_items()
    |> maybe_assign_metrics()
    |> apply_index_return_to()
  end

  defp assign_changeset(socket, fields) do
    %{
      item: item,
      changeset_function: changeset_function,
      live_action: live_action
    } = socket.assigns

    metadata = Resource.build_changeset_metadata(socket.assigns)
    changeset = changeset_function.(item, default_attrs(live_action, fields, socket.assigns), metadata)

    socket
    |> assign(:changeset, changeset)
  end

  defp default_attrs(:new, fields, %{schema: schema} = assigns) do
    Enum.reduce(fields, %{}, fn
      {name, %{default: default} = field_options} = field, attrs ->
        if field_options.module.association?(field) && schema.__schema__(:association, name).cardinality == :one do
          owner_key = schema.__schema__(:association, name).owner_key

          Map.put(attrs, owner_key, default.(assigns))
        else
          Map.put(attrs, name, default.(assigns))
        end

      _field, attrs ->
        attrs
    end)
  end

  defp default_attrs(:resource_action, fields, assigns) do
    Enum.reduce(fields, %{}, fn
      {name, %{default: default} = _field}, attrs ->
        Map.put(attrs, name, default.(assigns))

      _field, attrs ->
        attrs
    end)
  end

  defp default_attrs(_live_action, _fields, _assigns), do: %{}

  defp maybe_redirect_to_default_filters(%{assigns: %{filters_changed: false}} = socket) do
    %{
      live_resource: live_resource,
      query_options: query_options,
      params: params,
      filters: filters
    } = socket.assigns

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
      push_navigate(socket, to: to)
    else
      socket
    end
  end

  defp maybe_redirect_to_default_filters(socket) do
    socket
  end

  defp maybe_put_search(query_options, %{"search" => search} = _params)
       when is_nil(search) or search == "",
       do: query_options

  defp maybe_put_search(query_options, %{"search" => search} = _params),
    do: Map.put(query_options, :search, search)

  defp maybe_put_search(query_options, _params), do: query_options

  @impl Phoenix.LiveView
  def handle_event("close-modal", _params, socket) do
    socket =
      socket
      |> push_patch(to: socket.assigns.return_to)

    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("item-action", %{"action-key" => key, "item-id" => item_id}, socket) do
    item =
      Enum.find(socket.assigns.items, fn item ->
        to_string(primary_value(socket, item)) == to_string(item_id)
      end)

    socket
    |> assign(selected_items: [item])
    |> maybe_handle_item_action(key)
  end

  @impl Phoenix.LiveView
  def handle_event("item-action", %{"action-key" => key}, socket) do
    maybe_handle_item_action(socket, key)
  end

  @impl Phoenix.LiveView
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

    socket = push_patch(socket, to: to, replace: true)

    {:noreply, socket}
  end

  @impl Phoenix.LiveView
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

    socket = push_patch(socket, to: to, replace: true)

    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("change-filter", params, socket) do
    query_options = socket.assigns.query_options

    empty_filter_name = Atom.to_string(@empty_filter_key)

    filters =
      Map.get(query_options, :filters, %{})
      |> Map.merge(params["filters"])
      # Filter manually emptied filters and empty filter
      |> Enum.filter(fn
        {^empty_filter_name, _value} -> false
        {_filter, ""} -> false
        {_filter, %{"start" => "", "end" => ""}} -> false
        _filter_params -> true
      end)

    to =
      Router.get_path(
        socket,
        socket.assigns.live_resource,
        socket.assigns.params,
        :index,
        Map.put(query_options, :filters, filters)
      )

    socket =
      socket
      |> assign(filters_changed: true)
      |> push_patch(to: to)

    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("clear-filter", %{"field" => field}, socket) do
    %{live_resource: live_resource, query_options: query_options, params: params} = socket.assigns

    new_query_options =
      Map.put(
        query_options,
        :filters,
        Map.get(query_options, :filters, %{})
        |> Map.delete(field)
        |> maybe_put_empty_filter(@empty_filter_key)
      )

    to = Router.get_path(socket, live_resource, params, :index, new_query_options)

    socket =
      push_patch(socket, to: to)
      |> assign(params: Map.merge(params, new_query_options))
      |> assign(query_options: new_query_options)
      |> assign(filters_changed: true)

    {:noreply, socket}
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
      |> Map.drop([Atom.to_string(@empty_filter_key)])

    to =
      Router.get_path(
        socket,
        socket.assigns.live_resource,
        socket.assigns.params,
        :index,
        Map.put(query_options, :filters, filters)
      )

    socket =
      socket
      |> assign(filters_changed: true)
      |> push_patch(to: to)

    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("update-selected-items", %{"id" => id}, socket) do
    selected_items = socket.assigns.selected_items

    item = Enum.find(socket.assigns.items, fn item -> to_string(primary_value(socket, item)) == to_string(id) end)

    updated_selected_items =
      if Enum.member?(selected_items, item) do
        List.delete(selected_items, item)
      else
        [item | selected_items]
      end

    select_all = length(updated_selected_items) == length(socket.assigns.items)

    socket =
      socket
      |> assign(:selected_items, updated_selected_items)
      |> assign(:select_all, select_all)

    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("toggle-item-selection", _params, socket) do
    select_all = not socket.assigns.select_all

    selected_items =
      if select_all do
        socket.assigns.items
      else
        []
      end

    socket =
      socket
      |> assign(:select_all, select_all)
      |> assign(:selected_items, selected_items)

    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_info({:put_assoc, {key, value} = _assoc}, socket) do
    changeset = Ecto.Changeset.put_assoc(socket.assigns.changeset, key, value)
    assocs = Map.get(socket.assigns, :assocs, []) |> Keyword.put(key, value)

    socket =
      socket
      |> assign(:assocs, assocs)
      |> assign(:changeset, changeset)

    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_info({:put_embed, {key, value} = _assoc}, socket) do
    changeset = Ecto.Changeset.put_embed(socket.assigns.changeset, key, value)
    embeds = Map.get(socket.assigns, :embeds, []) |> Keyword.put(key, value)

    socket =
      socket
      |> assign(:embeds, embeds)
      |> assign(:changeset, changeset)

    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_info({:update_changeset, changeset}, socket) do
    {:noreply, assign(socket, :changeset, changeset)}
  end

  @impl Phoenix.LiveView
  def handle_info({"backpex:" <> event, item}, socket) do
    event_prefix = socket.assigns.live_resource.config(:pubsub)[:event_prefix]
    ^event_prefix <> event_type = event

    handle_backpex_info({event_type, item}, socket)
  end

  @impl Phoenix.LiveView
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  defp handle_backpex_info({"created", _item}, socket) when socket.assigns.live_action in [:index, :resource_action] do
    {:noreply, refresh_items(socket)}
  end

  defp handle_backpex_info({"deleted", item}, socket) when socket.assigns.live_action in [:index, :resource_action] do
    %{items: items} = socket.assigns

    if Enum.filter(items, &(to_string(primary_value(socket, &1)) == to_string(primary_value(socket, item)))) != [] do
      {:noreply, refresh_items(socket)}
    else
      {:noreply, socket}
    end
  end

  defp handle_backpex_info({"updated", item}, socket)
       when socket.assigns.live_action in [:index, :resource_action, :show] do
    {:noreply, update_item(socket, item)}
  end

  defp refresh_items(socket) do
    %{
      live_resource: live_resource,
      schema: schema,
      params: params,
      fields: fields,
      query_options: query_options
    } = socket.assigns

    filters = active_filters(socket.assigns)
    valid_filter_params = get_valid_filters_from_params(params, filters, @empty_filter_key)

    count_criteria = [
      search: search_options(params, fields, schema),
      filters: filter_options(valid_filter_params, filters)
    ]

    item_count = Resource.count(fields, socket.assigns, live_resource, count_criteria)
    %{page: page, per_page: per_page} = query_options
    total_pages = calculate_total_pages(item_count, per_page)
    new_query_options = Map.put(query_options, :page, validate_page(page, total_pages))

    socket
    |> assign(:item_count, item_count)
    |> assign(:total_pages, total_pages)
    |> assign(:query_options, new_query_options)
    |> assign_items()
    |> maybe_assign_metrics()
  end

  defp update_item(socket, item) do
    %{
      live_resource: live_resource,
      live_action: live_action
    } = socket.assigns

    item_primary_value = primary_value(socket, item)
    item = Resource.get(item_primary_value, socket.assigns, live_resource)

    socket =
      cond do
        live_action in [:index, :resource_action] and item ->
          items =
            Enum.map(socket.assigns.items, &if(primary_value(socket, &1) == item_primary_value, do: item, else: &1))

          assign(socket, :items, items)

        live_action == :show and item ->
          assign(socket, :item, item)

        true ->
          socket
      end

    socket
  end

  defp maybe_handle_item_action(socket, key) do
    key = String.to_existing_atom(key)
    action = socket.assigns.item_actions[key]
    items = socket.assigns.selected_items

    if has_modal?(action.module) do
      open_action_confirm_modal(socket, action, key)
    else
      handle_item_action(socket, action, key, items)
    end
  end

  defp open_action_confirm_modal(socket, action, key) do
    init_change = action.module.init_change(socket.assigns)
    changeset_function = &action.module.changeset/3

    metadata = Resource.build_changeset_metadata(socket.assigns)

    changeset =
      init_change
      |> Ecto.Changeset.change()
      |> changeset_function.(%{}, metadata)

    socket =
      socket
      |> assign(:item_action_types, init_change)
      |> assign(:changeset_function, changeset_function)
      |> assign(:changeset, changeset)
      |> assign(:action_to_confirm, Map.put(action, :key, key))

    {:noreply, socket}
  end

  defp handle_item_action(socket, action, key, items) do
    %{live_resource: live_resource} = socket.assigns
    items = Enum.filter(items, fn item -> live_resource.can?(socket.assigns, key, item) end)

    socket
    |> assign(action_to_confirm: nil)
    |> assign(selected_items: [])
    |> assign(select_all: false)
    |> action.module.handle(items, %{})
  end

  defp primary_value(socket, item) do
    primary_key = socket.assigns.live_resource.config(:primary_key)

    Map.get(item, primary_key)
  end

  @doc """
  Subscribes to pubsub topic.
  """
  def subscribe_to_topic(socket, name: name, topic: topic, event_prefix: _event_prefix) do
    if Phoenix.LiveView.connected?(socket) do
      Phoenix.PubSub.subscribe(name, topic)
    end
  end

  @doc """
  Returns order options by params.

  ## Examples

      iex> Backpex.LiveResource.order_options_by_params(%{"order_by" => "field", "order_direction" => "asc"}, [field: %{}], %{by: :id, direction: :asc}, %{}, [:asc, :desc])
      %{order_by: :field, order_direction: :asc}
      iex> Backpex.LiveResource.order_options_by_params(%{}, [field: %{}], %{by: :id, direction: :desc}, %{}, [:asc, :desc])
      %{order_by: :id, order_direction: :desc}
      iex> Backpex.LiveResource.order_options_by_params(%{"order_by" => "field", "order_direction" => "asc"}, [field: %{orderable: false}], %{by: :id, direction: :asc}, %{}, [:asc, :desc])
      %{order_by: :id, order_direction: :asc}
  """
  def order_options_by_params(params, fields, init_order, assigns, permitted_order_directions) do
    init_order = resolve_init_order(init_order, assigns)

    order_by =
      params
      |> Map.get("order_by")
      |> maybe_to_atom()
      |> value_in_permitted_or_default(
        orderable_fields(fields),
        Map.get(init_order, :by)
      )

    order_direction =
      params
      |> Map.get("order_direction")
      |> maybe_to_atom()
      |> value_in_permitted_or_default(
        permitted_order_directions,
        Map.get(init_order, :direction)
      )

    %{order_by: order_by, order_direction: order_direction}
  end

  @doc """
  Returns all orderable fields. A field is orderable by default.

  ## Example
      iex> Backpex.LiveResource.orderable_fields([field1: %{orderable: true}])
      [:field1]
      iex> Backpex.LiveResource.orderable_fields([field1: %{}])
      [:field1]
      iex> Backpex.LiveResource.orderable_fields([field1: %{orderable: false}])
      []
  """
  def orderable_fields(fields) do
    fields
    |> Keyword.filter(fn {_name, field} -> Map.get(field, :orderable, true) end)
    |> Enum.map(fn {name, _field_options} -> name end)
  end

  @doc """
  Returns all searchable fields. A field is not searchable by default.

  ## Example
      iex> Backpex.LiveResource.searchable_fields([field1: %{searchable: true}])
      [:field1]
      iex> Backpex.LiveResource.searchable_fields([field1: %{}])
      []
      iex> Backpex.LiveResource.searchable_fields([field1: %{searchable: false}])
      []
  """
  def searchable_fields(fields) do
    fields
    |> Keyword.filter(fn {_name, field} -> Map.get(field, :searchable, false) end)
    |> Enum.map(fn {name, _field_options} -> name end)
  end

  @doc """
  Returns filtered fields by a certain action.

  ## Example
      iex> Backpex.LiveResource.filtered_fields_by_action([field1: %{label: "Field1"}, field2: %{label: "Field2"}], %{}, :index)
      [field1: %{label: "Field1"}, field2: %{label: "Field2"}]
      iex> Backpex.LiveResource.filtered_fields_by_action([field1: %{label: "Field1", except: [:show]}, field2: %{label: "Field2"}], %{}, :show)
      [field2: %{label: "Field2"}]
      iex> Backpex.LiveResource.filtered_fields_by_action([field1: %{label: "Field1", only: [:index]}, field2: %{label: "Field2"}], %{}, :show)
      [field2: %{label: "Field2"}]
  """
  def filtered_fields_by_action(fields, assigns, action) do
    fields
    |> Keyword.filter(fn {_name, field_options} ->
      can_view_field?(field_options, assigns) and filter_field_by_action(field_options, action)
    end)
  end

  defp can_view_field?(%{can?: can?} = _field_options, assigns), do: can?.(assigns)
  defp can_view_field?(_field_options, _assigns), do: true

  @doc """
  Returns all search options.
  """
  def search_options(params, fields, schema) do
    {
      Map.get(
        params,
        "search",
        Map.get(params, :search, "")
      ),
      fields
      |> Keyword.filter(fn {_name, field_options} -> Map.get(field_options, :searchable, false) end)
      |> Enum.map(fn {name, field_options} = field ->
        {name, Map.put(field_options, :queryable, field_options.module.schema(field, schema))}
      end)
    }
  end

  @doc """
  Returns all filter options.
  """
  def filter_options(%{"filters" => filters}, filter_configs),
    do: filter_options(%{filters: filters}, filter_configs)

  def filter_options(%{filters: ""}, _filter_configs), do: %{}
  def filter_options(%{filters: nil}, _filter_configs), do: %{}

  def filter_options(%{filters: filters}, filter_configs) do
    Enum.map(filters, fn {key, value} ->
      key_as_atom = String.to_existing_atom(key)

      %{
        field: String.to_existing_atom(key),
        value: value,
        filter_config: filter_configs |> Keyword.get(key_as_atom)
      }
    end)
  end

  def filter_options(_no_filters_present, _filter_configs), do: %{}

  def get_empty_filter_key, do: @empty_filter_key

  @doc """
  Checks whether a field is orderable or not.

  ## Examples

      iex> Backpex.LiveResource.orderable?({:name, %{orderable: true}})
      true
      iex> Backpex.LiveResource.orderable?({:name, %{orderable: false}})
      false
      iex> Backpex.LiveResource.orderable?({:name, %{}})
      true
      iex> Backpex.LiveResource.orderable?(nil)
      false
  """
  def orderable?(field) when is_nil(field), do: false
  def orderable?({_name, field_options}), do: Map.get(field_options, :orderable, true)

  @doc """
  TODO: make private?
  """
  def build_criteria(assigns) do
    %{
      schema: schema,
      fields: fields,
      filters: filters,
      query_options: query_options,
      init_order: init_order
    } = assigns

    field = Enum.find(fields, fn {name, _field_options} -> name == query_options.order_by end)

    order =
      if orderable?(field) do
        {field_name, field_options} = field

        %{
          by: field_options.module.display_field(field),
          schema: field_options.module.schema(field, schema),
          direction: query_options.order_direction,
          field_name: field_name
        }
      else
        init_order
        |> resolve_init_order(assigns)
        |> Map.put(:schema, schema)
      end

    [
      order: order,
      pagination: %{page: query_options.page, size: query_options.per_page},
      search: search_options(query_options, fields, schema),
      filters: filter_options(query_options, filters)
    ]
  end

  @doc """
  Resolves the initial order configuration.

  ## Examples

      iex> Backpex.LiveResource.resolve_init_order(%{by: :name, direction: :asc}, %{})
      %{by: :name, direction: :asc}

      iex> Backpex.LiveResource.resolve_init_order(fn _ -> %{by: :age, direction: :desc} end, %{})
      %{by: :age, direction: :desc}

      iex> Backpex.LiveResource.resolve_init_order(fn assigns -> fn _ -> %{by: assigns.sort_by, direction: :asc} end end, %{sort_by: :date})
      ** (ArgumentError) init_order function should not return another function

      iex> Backpex.LiveResource.resolve_init_order(:invalid, %{})
      ** (ArgumentError) init_order must be a map with keys :by and :direction, or a function returning such a map. Got: :invalid
  """
  def resolve_init_order(init_order, assigns) when is_function(init_order, 1) do
    init_order = init_order.(assigns)

    # check if result is another function to prevent infinite loop
    if is_function(init_order, 1) do
      raise ArgumentError, "init_order function should not return another function"
    end

    resolve_init_order(init_order, assigns)
  end

  def resolve_init_order(%{by: _by, direction: _dir} = init_order, _assigns) do
    init_order
  end

  def resolve_init_order(init_order, _assigns) do
    raise ArgumentError,
          "init_order must be a map with keys :by and :direction, or a function returning such a map. Got: #{inspect(init_order)}"
  end

  @doc """
  Parses integer text representation map value of the given key. If the map does not contain the given key or parsing fails
  the default value is returned.

  ## Examples

      iex> Backpex.LiveResource.parse_integer(%{number: "1"}, :number, 2)
      1
      iex> Backpex.LiveResource.parse_integer(%{number: "abc"}, :number, 1)
      1
  """
  def parse_integer(map, key, default) do
    if Map.has_key?(map, key) do
      case map |> Map.get(key) |> Integer.parse() do
        {value, _reminder} -> value
        :error -> default
      end
    else
      default
    end
  end

  @doc """
  Filters a field by a given action. It checks whether the field contains the only or
  except key and decides whether or not to keep the field.

  ## Examples

      iex> Backpex.LiveResource.filter_field_by_action(%{only: [:index]}, :index)
      true
      iex> Backpex.LiveResource.filter_field_by_action(%{only: [:edit]}, :index)
      false
      iex> Backpex.LiveResource.filter_field_by_action(%{except: [:edit]}, :index)
      true
      iex> Backpex.LiveResource.filter_field_by_action(%{except: [:index]}, :index)
      false
  """
  def filter_field_by_action(field_options, action) do
    cond do
      Map.has_key?(field_options, :only) -> Enum.member?(field_options.only, action)
      Map.has_key?(field_options, :except) -> !Enum.member?(field_options.except, action)
      true -> true
    end
  end

  @doc """
  Calculates the total amount of pages.

  ## Examples

      iex> Backpex.LiveResource.calculate_total_pages(1, 2)
      1
      iex> Backpex.LiveResource.calculate_total_pages(10, 10)
      1
      iex> Backpex.LiveResource.calculate_total_pages(20, 10)
      2
      iex> Backpex.LiveResource.calculate_total_pages(25, 6)
      5
  """
  def calculate_total_pages(items_length, per_page),
    do: ceil(items_length / per_page)

  @doc """
  Validates a page number.

  ## Examples

      iex> Backpex.LiveResource.validate_page(1, 5)
      1
      iex> Backpex.LiveResource.validate_page(-1, 5)
      1
      iex> Backpex.LiveResource.validate_page(6, 5)
      5
  """
  def validate_page(_page, 0), do: 1

  def validate_page(page, total_pages) do
    cond do
      page < 1 -> 1
      page > total_pages -> total_pages
      true -> page
    end
  end

  @doc """
  Checks whether the given value is in a list of permitted values. Otherwise return default value.

  ## Examples
      iex> Backpex.LiveResource.value_in_permitted_or_default(3, [1, 2, 3], 5)
      3
      iex> Backpex.LiveResource.value_in_permitted_or_default(3, [1, 2], 5)
      5
  """
  def value_in_permitted_or_default(value, permitted, default) do
    if value in permitted, do: value, else: default
  end

  def default_item_actions do
    [
      show: %{
        module: Backpex.ItemActions.Show,
        only: [:row]
      },
      edit: %{
        module: Backpex.ItemActions.Edit,
        only: [:row, :show]
      },
      delete: %{
        module: Backpex.ItemActions.Delete,
        only: [:row, :index, :show]
      }
    ]
  end

  def maybe_put_empty_filter(%{} = filters, empty_filter_key) when filters == %{} do
    Map.put(filters, Atom.to_string(empty_filter_key), true)
  end

  def maybe_put_empty_filter(filters, _empty_filter_key) do
    filters
  end

  @doc """
  Returns list of filter options from query options
  """
  def get_filter_options(query_options) do
    query_options
    |> Map.get(:filters, %{})
    |> Map.drop([Atom.to_string(get_empty_filter_key())])
  end

  @doc """
  Returns list of active filters.
  """
  def active_filters(assigns) do
    filters = assigns.live_resource.filters(assigns)

    Enum.filter(filters, fn {key, option} ->
      get_empty_filter_key() != key and option.module.can?(assigns)
    end)
  end

  def get_valid_filters_from_params(%{"filters" => filters} = params, valid_filters, empty_filter_key) do
    valid_filters = Keyword.put(valid_filters, empty_filter_key, %{})

    filters =
      valid_filters
      |> Enum.reduce(%{}, fn {key, _val}, acc ->
        string_key = Atom.to_string(key)

        if Map.has_key?(filters, string_key) do
          value = Map.get(filters, string_key)

          Map.put(acc, string_key, value)
        else
          acc
        end
      end)

    Map.put(params, "filters", filters)
  end

  def get_valid_filters_from_params(_params, _valid_filters, _empty_filter_key), do: %{}

  defp maybe_to_atom(nil), do: nil
  defp maybe_to_atom(value), do: String.to_existing_atom(value)
end
