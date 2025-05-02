defmodule Backpex.LiveResource do
  @moduledoc ~S'''
  A LiveResource makes it easy to manage existing resources in your application. It provides extensive configuration options in order to meet everyone's needs. In connection with `Backpex.Components` you can build an individual admin dashboard on top of your application in minutes.

  > #### `use Backpex.LiveResource` {: .info}
  >
  > When you `use Backpex.LiveResource`, the `Backpex.LiveResource` module will set `@behavior Backpex.LiveResource`. Additionally it will create a LiveView based on the given configuration in order to create fully functional index, show, new and edit views for a resource. It will also insert fallback functions that can be overridden.
  '''

  use Phoenix.LiveView

  import Backpex.HTML.Resource

  alias Backpex.Resource
  alias Backpex.Router

  require Backpex

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
      required: false,
      keys: [
        server: [
          doc: "PubSub server of the project.",
          required: false,
          type: :atom
        ],
        topic: [
          doc: """
          The topic for PubSub.

          By default a stringified version of the live resource module name is used.
          """,
          required: false,
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
      doc: "If the layout fills out the entire width.",
      type: :boolean,
      default: false
    ],
    full_text_search: [
      doc: "The name of the generated column used for full text search.",
      type: :atom,
      default: nil
    ],
    save_and_continue_button?: [
      doc: "If the \"Save & Continue editing\" button is shown on form views.",
      type: :boolean,
      default: false
    ],
    on_mount: [
      doc: """
      An optional list of hooks to attach to the mount lifecycle. Passing a single value is also accepted.
      See https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html#on_mount/1
      """,
      type: {:or, [:mod_arg, :atom, {:list, :mod_arg}, {:list, :atom}]},
      required: false
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
  The function that can be used to add content to certain positions on Backpex views. It may also be used to overwrite content.

  See the following list for the available positions and the corresponding actions:

  - all actions
    - `:before_page_title`
    - `:page_title`
    - `:before_main`
    - `:main`
    - `:after_main`
  - `:index` action
    - `:before_actions`
    - `:actions`
    - `:before_filters`
    - `:filters`
    - `:before_metrics`
    - `:metrics`
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
  This function navigates to the specified path when an item has been created or updated. Defaults to the previous resource path (index or show).
  """
  @callback return_to(
              socket :: Phoenix.LiveView.Socket.t(),
              assigns :: map(),
              live_action :: atom(),
              form_action :: atom(),
              item :: map()
            ) ::
              binary()

  @doc """
  This function can be used to provide custom translations for texts. See the [translations guide](/guides/translations/translations.md#modify-strings) for detailed information.

  ## Examples

      # in your LiveResource

      @impl Backpex.LiveResource
      def translate({"Cancel", _opts}), do: gettext("Go back")
      def translate({"Save", _opts}), do: gettext("Continue")
      def translate({"New %{resource}", opts}), do: gettext("Create %{resource}", opts)
  """
  @callback translate(msg :: tuple()) :: binary()

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
      import Backpex.LiveResource
      import Phoenix.LiveView.Helpers

      alias Backpex.LiveResource

      require Backpex

      def config(key), do: Keyword.get(@resource_opts, key)

      def pubsub, do: LiveResource.pubsub(__MODULE__)

      def validated_fields, do: LiveResource.validated_fields(__MODULE__)

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

      defoverridable can?: 3,
                     fields: 0,
                     filters: 0,
                     filters: 1,
                     resource_actions: 0,
                     item_actions: 1,
                     index_row_class: 4

      live_resource = __MODULE__

      for action <- ~w(Index Form Show)a do
        defmodule String.to_atom("#{__MODULE__}.#{action}") do
          @resource_opts NimbleOptions.validate!(opts, options_schema)

          use Phoenix.LiveView, layout: @resource_opts[:layout]

          @action_module String.to_existing_atom("Elixir.Backpex.LiveResource.#{action}")

          insert_on_mount_hooks(@resource_opts[:on_mount])

          def mount(params, session, socket), do: @action_module.mount(params, session, socket, unquote(live_resource))
          def handle_params(params, url, socket), do: @action_module.handle_params(params, url, socket)
          def render(assigns), do: @action_module.render(assigns)
          def handle_info(msg, socket), do: @action_module.handle_info(msg, socket)
          def handle_event(event, params, socket), do: @action_module.handle_event(event, params, socket)
        end
      end
    end
  end

  defmacro insert_on_mount_hooks(hooks) do
    quote bind_quoted: [hooks: hooks] do
      case hooks do
        hooks when is_nil(hooks) -> nil
        hooks when is_list(hooks) -> for hook <- hooks, do: on_mount(hook)
        hook -> on_mount hook
      end
    end
  end

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defmacro __before_compile__(_env) do
    quote do
      import Backpex.HTML.Layout
      import Backpex.HTML.Resource

      alias Backpex.LiveResource
      alias Backpex.Router

      @impl Backpex.LiveResource
      def panels, do: []

      @impl Backpex.LiveResource
      def metrics, do: []

      @impl Backpex.LiveResource
      def on_item_created(socket, _item), do: socket

      @impl Backpex.LiveResource
      def on_item_updated(socket, _item), do: socket

      @impl Backpex.LiveResource
      def on_item_deleted(socket, _item), do: socket

      @impl Backpex.LiveResource
      def return_to(socket, assigns, _live_action, _form_action, _item) do
        Map.get(assigns, :return_to, Router.get_path(socket, assigns.live_resource, assigns.params, :index))
      end

      @impl Backpex.LiveResource
      def render_resource_slot(var!(assigns), :index, :page_title) do
        ~H"""
        <.main_title>
          {@page_title}
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
        <.resource_filters search_placeholder={Backpex.__("Search", @live_resource)} {assigns} />
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
          {@page_title}
          <.link
            :if={@live_resource.can?(assigns, :edit, @item)}
            id={"#{@live_resource.singular_name()}-edit-link"}
            phx-hook="BackpexTooltip"
            data-tooltip={Backpex.__("Edit", @live_resource)}
            aria-label={Backpex.__("Edit", @live_resource)}
            patch={Router.get_path(@socket, @live_resource, @params, :edit, @item)}
          >
            <Backpex.HTML.CoreComponents.icon
              name="hero-pencil-square"
              class="h-6 w-6 cursor-pointer transition duration-75 hover:text-primary hover:scale-110"
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
          {@page_title}
        </.main_title>
        """
      end

      @impl Backpex.LiveResource
      def render_resource_slot(var!(assigns), :new, :page_title) do
        ~H"""
        <.main_title class="mb-4">
          {@page_title}
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

      @impl Backpex.LiveResource
      def translate({msg, opts}), do: Backpex.translate({msg, opts})
    end
  end

  @doc """
  Returns the fields of the given `Backpex.LiveResource` validated against each fields config schema.
  """
  def validated_fields(live_resource) do
    live_resource.fields()
    |> Enum.map(fn {name, options} = field ->
      options.module.validate_config!(field, live_resource)
      |> Enum.into(%{})
      |> then(&{name, &1})
    end)
  end

  def assign_changeset(socket, changeset_function, item, fields, live_action) do
    metadata = Resource.build_changeset_metadata(socket.assigns)
    changeset = changeset_function.(item, default_attrs(live_action, fields, socket.assigns), metadata)

    assign(socket, :changeset, changeset)
  end

  def default_attrs(:new, fields, assigns) do
    adapter_config = assigns.live_resource.config(:adapter_config)
    schema = adapter_config[:schema]

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

  def default_attrs(:resource_action, fields, assigns) do
    Enum.reduce(fields, %{}, fn
      {name, %{default: default} = _field}, attrs ->
        Map.put(attrs, name, default.(assigns))

      _field, attrs ->
        attrs
    end)
  end

  def default_attrs(_live_action, _fields, _assigns), do: %{}

  def handle_event("change-filter", params, socket) do
    query_options = socket.assigns.query_options

    empty_filter_name = Atom.to_string(empty_filter_key())

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

    socket
    |> assign(filters_changed: true)
    |> push_patch(to: to)
    |> noreply()
  end

  def primary_value(item, live_resource) do
    Map.get(item, live_resource.config(:primary_key))
  end

  @doc """
  Returns the pubsub settings for the current LiveResource.
  """
  def pubsub(live_resource) do
    [
      server: live_resource.config(:pubsub)[:server] || Application.fetch_env!(:backpex, :pubsub_server),
      topic: live_resource.config(:pubsub)[:topic] || to_string(live_resource)
    ]
  end

  @doc """
  Returns order options by params.

  ## Examples

      iex> Backpex.LiveResource.order_options_by_params(%{"order_by" => "field", "order_direction" => "asc"}, [field: %{}], %{by: :id, direction: :asc}, %{})
      %{order_by: :field, order_direction: :asc}
      iex> Backpex.LiveResource.order_options_by_params(%{}, [field: %{}], %{by: :id, direction: :desc}, %{})
      %{order_by: :id, order_direction: :desc}
      iex> Backpex.LiveResource.order_options_by_params(%{"order_by" => "field", "order_direction" => "asc"}, [field: %{orderable: false}], %{by: :id, direction: :asc}, %{})
      %{order_by: :id, order_direction: :asc}
  """
  def order_options_by_params(params, fields, init_order, assigns) do
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
        permitted_order_directions(),
        Map.get(init_order, :direction)
      )

    %{order_by: order_by, order_direction: order_direction}
  end

  defp permitted_order_directions, do: ~w(asc desc)a

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

  def empty_filter_key, do: :empty_filter

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

  def build_criteria(assigns) do
    %{
      live_resource: live_resource,
      fields: fields,
      filters: filters,
      query_options: query_options,
      init_order: init_order
    } = assigns

    adapter_config = live_resource.config(:adapter_config)
    field = Enum.find(fields, fn {name, _field_options} -> name == query_options.order_by end)

    order =
      if orderable?(field) do
        {field_name, field_options} = field

        %{
          by: field_options.module.display_field(field),
          schema: field_options.module.schema(field, adapter_config[:schema]),
          direction: query_options.order_direction,
          field_name: field_name
        }
      else
        init_order
        |> resolve_init_order(assigns)
        |> Map.put(:schema, adapter_config[:schema])
      end

    [
      order: order,
      pagination: %{page: query_options.page, size: query_options.per_page},
      search: search_options(query_options, fields, adapter_config[:schema]),
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

  @doc """
  Returns list of filter options from query options
  """
  def get_filter_options(query_options) do
    query_options
    |> Map.get(:filters, %{})
    |> Map.drop([Atom.to_string(empty_filter_key())])
  end

  @doc """
  Returns list of active filters.
  """
  def active_filters(assigns) do
    filters = assigns.live_resource.filters(assigns)

    Enum.filter(filters, fn {key, option} ->
      empty_filter_key() != key and option.module.can?(assigns)
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
