defmodule Backpex.LiveResource do
  @moduledoc ~S'''
  A LiveResource makes it easy to manage existing resources in your application. It provides extensive configuration options in order to meet everyone's needs. In connection with `Backpex.Components` you can build an individual admin dashboard on top of your application in minutes.

  > #### `use Backpex.LiveResource` {: .info}
  >
  > When you `use Backpex.LiveResource`, the `Backpex.LiveResource` module will set `@behavior Backpex.LiveResource`. Additionally it will create a LiveView based on the given configuration in order to create fully functional index, show, new and edit views for a resource. It will also insert fallback functions that can be overridden.
  '''

  use Phoenix.LiveView

  alias Backpex.Resource
  alias Backpex.Router
  alias Phoenix.LiveView.Rendered
  alias Phoenix.LiveView.Socket

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
      type: {:or, [:mod_arg, {:fun, 1}]},
      required: false,
      deprecated: "Use the layout/1 callback instead to avoid compile-time dependencies."
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
      doc: """
      Order that will be used when no other order options are given.

      Defaults to ascending order by the configured `primary_key`.
      """,
      type: {
        :or,
        [
          {:in, [nil]},
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
      default: nil
    ],
    order_nulls: [
      doc: """
      Where `NULL` values are placed when the index view is ordered by a column.

      - `:default` uses the database default. PostgreSQL treats `NULL` as larger than any value, so `NULL` values come
        last in ascending and first in descending order.
      - `:first` places `NULL` values first in both directions (`NULLS FIRST`).
      - `:last` places `NULL` values last in both directions (`NULLS LAST`).
      - `:smallest` treats `NULL` as smaller than any value: first in ascending (`ASC NULLS FIRST`) and last in
        descending order (`DESC NULLS LAST`). This was the behaviour before v0.23.

      Fields can override this with their own `:order_nulls` option. Ordering by the `primary_key` always uses the
      database default, since a primary key is never `NULL`. `:first`, `:last` and `:smallest` need a matching index (e.g.
      `create index(:posts, ["published_at NULLS FIRST"])`), otherwise the database sorts the whole table on every
      page load. See the [Ordering](live_resource/ordering.md) guide.
      """,
      type: {:in, [:default, :first, :last, :smallest]},
      default: :default
    ],
    context_assigns: [
      doc: """
      The assigns that callbacks receive while the index and show views are rendered, e.g. `c:can?/3`,
      `c:index_row_class/4`, the callbacks of item actions, the `render/1` and `render_form/1` callbacks of filters, and
      the functions and callbacks of fields. `c:filters/1` and the `can?/1` callback of filters always receive all
      assigns. `:all` passes every assign. A list of keys is added to the assigns Backpex always passes
      (`:live_resource`, `:live_action`, `:params`, `:fields`, `:item_actions`, `:return_to`, the `:item` of the show
      view, which is `nil` on the index view or the `base_schema` of a resource action while one is open, and a
      `:socket` for building routes). The functions and callbacks of fields on the index view receive the item of their
      row as `:item` instead.
      With a list, LiveView only re-renders the parts using these callbacks when one of these assigns changes, instead
      of on every change of the LiveView. See the [Context Assigns](live_resource/context-assigns.md) guide.
      """,
      type: {:or, [{:in, [:all]}, {:list, :atom}]},
      default: :all
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
      type: {:or, [:mod_arg, :atom, {:list, {:or, [:mod_arg, :atom]}}]},
      required: false
    ],
    persist: [
      doc: """
      Opt in to persisting index-view state (`:order`, `:filters`, `:columns`, `:metrics`)
      via `Backpex.Preferences`. Accepts any subset of `[:order, :filters, :columns, :metrics]`.

      When empty (the default), the index view's state lives only in the URL (for
      `:order` and `:filters`) and in-memory (for `:columns` and `:metrics`). When an
      item is listed, Backpex reads the corresponding preference on mount and falls back
      to it whenever the URL-derived value is absent, and writes the preference on
      every change. Storage is routed through whichever adapter is configured for
      the `resource.*` prefix in `config :backpex, Backpex.Preferences, adapters:`.
      """,
      type: {:list, {:in, [:order, :filters, :columns, :metrics]}},
      default: []
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

  ## Enforcement

  Backpex enforces this callback centrally through `Backpex.Authorization`. It is evaluated both as a
  preflight check (to hide or disable controls) and as a hard gate immediately before an action runs:

  * `Backpex.Resource.insert/6` authorizes `:new` with a `nil` item.
  * `Backpex.Resource.update/6` authorizes `:edit` with the item.
  * `Backpex.Resource.delete_all/4` authorizes `:delete` per item.
  * `Backpex.Resource.update_all/5` authorizes `:edit` per item.
  * Item actions authorize their action key per item, resource actions authorize their key with a `nil` item.

  The default action can be overridden per call with the `:authorization_action` option, and skipped
  entirely with `authorize?: false` for system writes.

  Enforcement is strict: a single unauthorized item in a selection raises `Backpex.ForbiddenError`
  instead of silently dropping that item.

  Read operations (`:index`, `:show`) are enforced in the view layer only. `Backpex.Resource.list/4`,
  `Backpex.Resource.get/4` and `Backpex.Resource.count/4` do not call this callback.

  Return a boolean. Only `true` allows; `false` and `nil` deny, and any other value raises an
  `ArgumentError` instead of passing as truthy.
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
              %Rendered{}

  @doc """
  A optional keyword list of [filters](Backpex.Filter.html) to be used on the index view.
  """
  @callback filters() :: keyword()

  @doc """
  A optional keyword list of [filters](Backpex.Filter.html) to be used on the index view.
  """
  @callback filters(assigns :: map()) :: keyword()

  @doc """
  Defines the layout to be used by the LiveResource.

  Can be used instead of the `layout` option in `use Backpex.LiveResource` to avoid
  compile-time dependencies on layout modules. By default, returns the value of the `layout` option
  and raises if neither is configured.

  Must return either a `{module, function_name}` tuple or a function with arity 1.
  """
  @callback layout(assigns :: map()) :: {module(), atom()} | (map() -> Rendered.t())

  @doc """
  A list of metrics shown on the index view of your resource.
  """
  @callback metrics() :: keyword()

  @doc """
  This function is executed when an item has been created.
  """
  @callback on_item_created(socket :: Socket.t(), item :: map()) ::
              Socket.t()

  @doc """
  This function is executed when an item has been updated.
  """
  @callback on_item_updated(socket :: Socket.t(), item :: map()) ::
              Socket.t()

  @doc """
  This function is executed when an item has been deleted.
  """
  @callback on_item_deleted(socket :: Socket.t(), item :: map()) ::
              Socket.t()

  @doc """
  The submit buttons of the `:new` and `:edit` forms.

  Receives the assigns (including the `item` being edited) and the default actions — `:save` and,
  if `save_and_continue_button?` is enabled, `:continue` — and returns a keyword list of actions.
  Each action is a map with a `:label` and an optional `:soft` flag for a less prominent button.
  The buttons render in the given order.

  Every action saves the form. The key of the clicked button is passed as `form_action` to
  `c:return_to/5`, so each button can lead somewhere else. `:continue` keeps its built-in
  behavior and stays on the form.

  ## Example

      @impl Backpex.LiveResource
      def form_actions(%{item: %{status: :draft}}, _default_actions) do
        [
          save: %{label: "Save as draft", soft: true},
          publish: %{label: "Publish…"}
        ]
      end

      def form_actions(_assigns, default_actions), do: default_actions
  """
  @callback form_actions(assigns :: map(), default_actions :: keyword()) :: keyword()

  @doc """
  This function navigates to the specified path when an item has been created or updated. Defaults to the previous resource path (index or show).
  """
  @callback return_to(
              socket :: Socket.t(),
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
      @behaviour Backpex.LiveResource

      use BackpexWeb, :live_resource

      import Backpex.LiveResource
      import Phoenix.LiveView.Helpers

      alias Backpex.LiveResource

      require Backpex

      @before_compile Backpex.LiveResource
      @resource_opts NimbleOptions.validate!(opts, options_schema)

      @adapter_opts @resource_opts[:adapter].validate_config!(@resource_opts[:adapter_config])

      def config(:init_order) do
        @resource_opts[:init_order] ||
          %{by: @resource_opts[:primary_key], direction: :asc}
      end

      def config(key), do: Keyword.get(@resource_opts, key)

      def adapter_config(key), do: Keyword.get(@adapter_opts, key)

      def pubsub, do: LiveResource.pubsub(__MODULE__)

      def fields(live_action, assigns), do: LiveResource.fields(__MODULE__, live_action, assigns)

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
      def layout(_assigns) do
        case config(:layout) do
          nil ->
            raise ArgumentError,
                  "No layout configured for #{inspect(__MODULE__)}. " <>
                    "Define a layout/1 callback in #{inspect(__MODULE__)}."

          value ->
            value
        end
      end

      @impl Backpex.LiveResource
      def resource_actions, do: []

      @impl Backpex.LiveResource
      def item_actions(default_actions), do: default_actions

      @impl Backpex.LiveResource
      def form_actions(_assigns, default_actions), do: default_actions

      defoverridable can?: 3,
                     fields: 0,
                     filters: 0,
                     filters: 1,
                     layout: 1,
                     resource_actions: 0,
                     item_actions: 1,
                     form_actions: 2,
                     index_row_class: 4

      live_resource = __MODULE__

      for action <- ~w(Index Form Show)a do
        # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
        defmodule String.to_atom("#{__MODULE__}.#{action}") do
          use Phoenix.LiveView

          @resource_opts NimbleOptions.validate!(opts, options_schema)

          @action_module String.to_existing_atom("Elixir.Backpex.LiveResource.#{action}")

          insert_on_mount_hooks(@resource_opts[:on_mount])

          def mount(params, session, socket) do
            params
            |> @action_module.mount(session, socket, unquote(live_resource))
            |> maybe_put_context()
          end

          def handle_params(params, url, socket) do
            params
            |> @action_module.handle_params(url, socket)
            |> maybe_put_context()
          end

          def render(assigns), do: assigns |> maybe_put_context() |> @action_module.render()

          def handle_info(msg, socket), do: msg |> @action_module.handle_info(socket) |> maybe_put_context()

          def handle_event(event, params, socket) do
            event
            |> @action_module.handle_event(params, socket)
            |> maybe_put_context()
          end

          if action in [:Index, :Show] do
            defp maybe_put_context(result), do: LiveResource.put_context(result)
          else
            defp maybe_put_context(result), do: result
          end
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
    quote generated: true do
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
      def render_resource_slot(assigns, :index, :actions), do: resource_buttons_slot(assigns)

      @impl Backpex.LiveResource
      def render_resource_slot(assigns, :index, :filters), do: resource_filters_slot(assigns)

      @impl Backpex.LiveResource
      def render_resource_slot(assigns, :index, :metrics), do: resource_metrics_slot(assigns)

      @impl Backpex.LiveResource
      def render_resource_slot(assigns, :index, :main), do: resource_index_main_slot(assigns)

      @impl Backpex.LiveResource
      def render_resource_slot(var!(assigns), :show, :page_title) do
        ~H"""
        <div class="flex items-center justify-between">
          <.main_title>
            {@page_title}
          </.main_title>
          <div class="flex items-center space-x-2">
            <%= for {key, action} <- Backpex.HTML.Resource.filter_item_actions(@item_actions, :show),
                    Backpex.Authorization.can?(@live_resource, @backpex_view_context, key, @item) do %>
              <%= if Backpex.ItemAction.has_link?(action) do %>
                <.link
                  id={"item-action-#{key}"}
                  navigate={action.module.link(@backpex_view_context, @item)}
                  aria-label={action.module.label(@backpex_view_context, @item)}
                  phx-hook="BackpexTooltip"
                  data-tooltip={action.module.label(@backpex_view_context, @item)}
                  class="cursor-pointer leading-none"
                >
                  {action.module.icon(@backpex_view_context, @item)}
                </.link>
              <% else %>
                <button
                  id={"item-action-#{key}"}
                  type="button"
                  phx-click="item-action"
                  phx-value-action-key={key}
                  aria-label={action.module.label(@backpex_view_context, @item)}
                  phx-hook="BackpexTooltip"
                  data-tooltip={action.module.label(@backpex_view_context, @item)}
                  class="cursor-pointer leading-none"
                >
                  {action.module.icon(@backpex_view_context, @item)}
                </button>
              <% end %>
            <% end %>
          </div>
        </div>
        """
      end

      @impl Backpex.LiveResource
      def render_resource_slot(assigns, :show, :main), do: resource_show_main_slot(assigns)

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
  Returns the fields of the given `Backpex.LiveResource`.

  Each field is validated against each fields config schema and filtered by the `live_action` and
  the fields `can?` options.
  """
  def fields(live_resource, live_action, assigns) do
    live_resource
    |> validated_fields()
    |> fields_by_action(live_action)
    |> fields_by_can(assigns)
  end

  defp validated_fields(live_resource) do
    live_resource.fields()
    |> Enum.map(fn {name, options} = field ->
      options.module.validate_config!(field, live_resource)
      |> Map.new()
      |> then(&{name, &1})
    end)
  end

  def assign_changeset(socket, changeset_function, item, fields, live_action) do
    metadata = Resource.build_changeset_metadata(socket.assigns)
    changeset = changeset_function.(item, default_attrs(live_action, fields, socket.assigns), metadata)

    assign(socket, :changeset, changeset)
  end

  def default_attrs(:new, fields, assigns) do
    Enum.reduce(fields, %{}, fn
      {_name, %{default: default} = field_options} = field, attrs ->
        Map.put(attrs, default_attr_key(field, field_options, assigns.live_resource), default.(assigns))

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

  # The default of a field for a single associated item is the value of the key the association is based on.
  defp default_attr_key({name, _options} = field, field_options, live_resource) do
    with true <- field_options.module.association?(field),
         %{cardinality: :one, owner_key: owner_key} <- Resource.association(name, live_resource) do
      owner_key
    else
      _other -> name
    end
  end

  @context_assigns [:live_resource, :live_action, :params, :fields, :item_actions, :return_to, :item]

  @doc """
  Returns the assigns that callbacks receive while the index and show views are rendered. See the
  `:context_assigns` option.

  The context has no change tracking, like the assigns of a component rendered with `__changed__: nil`, so callbacks
  can still call `Phoenix.Component.assign/3` on it.
  """
  def context(%{live_resource: live_resource} = assigns) do
    case live_resource.config(:context_assigns) do
      :all ->
        untracked(assigns)

      keys ->
        assigns
        |> Map.take(@context_assigns ++ keys)
        |> Map.put(:socket, routing_socket(assigns))
        |> Map.put(:__changed__, nil)
    end
  end

  def context(assigns), do: untracked(assigns)

  @doc false
  def untracked(assigns) do
    assigns
    |> Map.drop([:__changed__, :backpex_view_context])
    |> Map.put(:__changed__, nil)
  end

  # The socket in the assigns of a render carries all assigns, so it would change the context on every render.
  # Building routes only needs the router and endpoint.
  defp routing_socket(%{socket: %Socket{} = socket}),
    do: %Socket{endpoint: socket.endpoint, router: socket.router, view: socket.view, host_uri: socket.host_uri}

  defp routing_socket(_assigns), do: nil

  @doc false
  def put_context({:ok, socket}), do: {:ok, put_context(socket)}
  def put_context({:ok, socket, opts}), do: {:ok, put_context(socket), opts}
  def put_context({:noreply, socket}), do: {:noreply, put_context(socket)}
  def put_context({:reply, reply, socket}), do: {:reply, reply, put_context(socket)}

  # With `:all`, the context changes on every render anyway. Keeping it out of the socket also keeps the socket
  # it contains from nesting the previous context.
  def put_context(%Socket{assigns: %{live_resource: live_resource} = assigns} = socket) do
    case live_resource.config(:context_assigns) do
      :all -> socket
      _keys -> Phoenix.Component.assign(socket, :backpex_view_context, context(Map.put(assigns, :socket, socket)))
    end
  end

  def put_context(%Socket{} = socket), do: socket

  def put_context(assigns) when is_map(assigns),
    do: Phoenix.Component.assign(assigns, :backpex_view_context, context(assigns))

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
      iex> Backpex.LiveResource.fields_by_action([field1: %{label: "Field1"}, field2: %{label: "Field2"}], :index)
      [field1: %{label: "Field1"}, field2: %{label: "Field2"}]
      iex> Backpex.LiveResource.fields_by_action([field1: %{label: "Field1", except: [:show]}, field2: %{label: "Field2"}], :show)
      [field2: %{label: "Field2"}]
      iex> Backpex.LiveResource.fields_by_action([field1: %{label: "Field1", only: [:index]}, field2: %{label: "Field2"}], :show)
      [field2: %{label: "Field2"}]
  """
  def fields_by_action(fields, :resource_action), do: fields_by_action(fields, :index)

  def fields_by_action(fields, action) do
    fields
    |> Keyword.filter(fn {_name, field_options} ->
      filter_field_by_action(field_options, action)
    end)
  end

  @doc """
  Returns filtered fields by the result of the implemented `can?` function.

  ## Example
      > Backpex.LiveResource.fields_by_can([field1: %{label: "Field1"}], %{})
      [field1: %{label: "Field1"}]
      > Backpex.LiveResource.fields_by_can([field1: %{label: "Field1", can?: fn _assigns -> true end}, field2: %{label: "Field2", can?: fn _assigns -> true end}], %{})
      [field1: %{label: "Field1"}, field2: %{label: "Field2"}]
      > Backpex.LiveResource.fields_by_can([field1: %{label: "Field1", can?: fn _assigns -> false end}, field2: %{label: "Field2", can?: fn _assigns -> true end}], %{})
      [field2: %{label: "Field2"}]
      > Backpex.LiveResource.fields_by_can([field1: %{label: "Field1", can?: fn _assigns -> false end}], %{})
      []

  """
  def fields_by_can(fields, assigns) do
    fields
    |> Keyword.filter(fn {_name, field_options} ->
      can_view_field?(field_options, assigns)
    end)
  end

  defp can_view_field?(%{can?: can?} = _field_options, assigns), do: can?.(assigns)
  defp can_view_field?(_field_options, _assigns), do: true

  @doc """
  Returns all search options: the search string and the searchable fields.
  """
  def search_options(params, fields) do
    {
      Map.get(
        params,
        "search",
        Map.get(params, :search, "")
      ),
      Keyword.filter(fields, fn {_name, field_options} -> Map.get(field_options, :searchable, false) end)
    }
  end

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
      filters: filters,
      query_options: query_options,
      init_order: init_order,
      fields: fields
    } = assigns

    # Get validated filter values from assigns, falling back to empty map
    filter_values = Map.get(assigns, :filter_values, %{})

    field = Enum.find(fields, fn {name, _field_options} -> name == query_options.order_by end)

    order =
      if orderable?(field) do
        {field_name, field_options} = field

        order = %{
          by: field_options.module.display_field(field),
          direction: query_options.order_direction,
          field_name: field_name
        }

        primary_key? =
          not field_options.module.association?(field) and not Map.has_key?(field_options, :select) and
            not Map.has_key?(field_options, :custom_alias) and order.by == live_resource.config(:primary_key)

        Map.put(order, :nulls, order_nulls(live_resource, field_options, primary_key?))
      else
        init_order = resolve_init_order(init_order, assigns)
        primary_key? = init_order.by == live_resource.config(:primary_key)

        Map.merge(init_order, %{
          field_name: nil,
          nulls: order_nulls(live_resource, %{}, primary_key?)
        })
      end

    [
      order: order,
      pagination: %{page: query_options.page, size: query_options.per_page},
      search: search_options(query_options, fields),
      filter_values: filter_values,
      filter_configs: filters
    ]
  end

  # A primary key is never NULL, so NULLS FIRST/LAST would only keep the database from using the primary key index.
  defp order_nulls(_live_resource, _field_options, true = _primary_key?), do: :default

  defp order_nulls(live_resource, field_options, false = _primary_key?) do
    Map.get(field_options, :order_nulls) || live_resource.config(:order_nulls) || :default
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
      result =
        map
        |> Map.get(key)
        |> Integer.parse()

      case result do
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
  def calculate_total_pages(items_length, per_page), do: ceil(items_length / per_page)

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
  Returns the raw filter options map from query options.

  This returns the filter values as stored in query_options, which may include
  both valid and invalid filter values (for form display purposes).
  """
  def get_filter_options(query_options) do
    Map.get(query_options, :filters, %{})
  end

  @doc """
  Returns list of active filters.

  Active filters are those defined in the LiveResource that the current user
  has permission to use (based on the filter's `can?/1` callback).
  """
  def active_filters(assigns) do
    filters = assigns.live_resource.filters(assigns)

    Enum.filter(filters, fn {_key, option} ->
      option.module.can?(assigns)
    end)
  end

  defp maybe_to_atom(nil), do: nil
  defp maybe_to_atom(value), do: String.to_existing_atom(value)

  @doc """
  Subscribes to PubSub if the socket is connected.
  """
  def maybe_subscribe_to_pubsub(socket, live_resource) do
    if Phoenix.LiveView.connected?(socket) do
      [server: server, topic: topic] = live_resource.pubsub()
      Phoenix.PubSub.subscribe(server, topic)
    end

    socket
  end

  @doc """
  Extracts a safe `return_to` path from the given params.

  Backpex uses the `return_to` value to determine where to navigate after an
  item has been created, updated, or acted on via an item action. By appending
  a `?return_to=` query parameter to a resource URL you can override that
  destination, e.g. to send the user back to the page they came from.

  Only same-origin, absolute paths are accepted. Any value carrying a scheme or
  host (`https://example.com`, `//example.com`, `/\\example.com`), or containing
  control characters, is rejected to prevent open redirects, in which case `nil`
  is returned and callers should fall back to their default destination.

  ## Examples

      iex> Backpex.LiveResource.return_to_param(%{"return_to" => "/admin/posts?page=2"})
      "/admin/posts?page=2"

      iex> Backpex.LiveResource.return_to_param(%{"return_to" => "https://evil.com"})
      nil

      iex> Backpex.LiveResource.return_to_param(%{"return_to" => "//evil.com"})
      nil

      iex> Backpex.LiveResource.return_to_param(%{"return_to" => "/\\evil.com"})
      nil

      iex> Backpex.LiveResource.return_to_param(%{})
      nil
  """
  def return_to_param(params) do
    case Map.get(params, "return_to") do
      path when is_binary(path) -> if safe_return_to?(path), do: path
      _other -> nil
    end
  end

  defp safe_return_to?("//" <> _rest), do: false
  defp safe_return_to?("/\\" <> _rest), do: false

  defp safe_return_to?("/" <> _rest = path) do
    uri = URI.parse(path)
    is_nil(uri.scheme) and is_nil(uri.host) and not String.match?(path, ~r/[[:cntrl:]]/)
  end

  defp safe_return_to?(_path), do: false

  # Resolves a client-supplied action key (from an event payload or the URL) against a keyword list
  # of registered item or resource actions.
  #
  # Returns `{key, action}` for the matching registration and raises `Backpex.NoResultsError` when
  # the key is not registered.
  #
  # The key is matched by comparing binaries rather than by `String.to_existing_atom/1`: a forged
  # key must produce the same 404 as an unknown one, not an `ArgumentError` that depends on which
  # atoms happen to exist in the running system.
  #
  # This parses an HTTP event, it is not LiveResource configuration API — hence `@doc false`.
  @doc false
  def fetch_action!(actions, key) when is_list(actions) and is_binary(key) do
    case Enum.find(actions, fn {registered_key, _action} -> Atom.to_string(registered_key) == key end) do
      nil -> raise Backpex.NoResultsError
      registration -> registration
    end
  end

  def fetch_action!(_actions, _key), do: raise(Backpex.NoResultsError)
end
