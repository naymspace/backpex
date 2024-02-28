# credo:disable-for-this-file Credo.Check.Refactor.LongQuoteBlocks
# credo:disable-for-this-file Credo.Check.Refactor.CyclomaticComplexity

defmodule Backpex.LiveResource do
  @moduledoc ~S'''
  LiveResource makes it easy to manage existing resources in your application.
  It provides extensive configuration options in order to meet everyone's needs.
  In connection with `Backpex.Components` you can build an individual admin dashboard
  on top of your application in minutes.


  ## Example

  Before you start make sure Backpex is properly configured.

  `Backpex.LiveResource` is the module that will generate the corresponding LiveViews for the resource you configured.
  You are required to set some general options to tell Backpex where to find the resource and what
  changesets should be used. In addition you have to provide names and a list of fields.

  A minimal configuration looks something like this:

      defmodule MyAppWeb.UserLive do
        use Backpex.LiveResource,
          layout: {MyAppWeb.LayoutView, :admin},
          schema: MyApp.User,
          repo: MyApp.Repo,
          update_changeset: &MyApp.User.update_changeset/3,
          create_changeset: &MyApp.User.create_changeset/3

        @impl Backpex.LiveResource
        def singular_name(), do: "User"

        @impl Backpex.LiveResource
        def plural_name(), do: "Users"

        @impl Backpex.LiveResource
        def fields do
        [
          username: %{
            module: Backpex.Fields.Text,
            label: "Username"
          },
          first_name: %{
            module: Backpex.Fields.Text,
            label: "First Name"
          },
          last_name: %{
            module: Backpex.Fields.Text,
            label: "Last Name"
          },
        ]
      end

  You are also required to configure your router in order to serve the generated LiveViews:

      defmodule MyAppWeb.Router
        import Backpex.Router

        scope "/admin", MyAppWeb do
          pipe_through :browser

          live_session :default, on_mount: Backpex.InitAssigns do
            live_resources("/users", UserLive)
          end
        end
      end

  > #### `use Backpex.LiveResource` {: .info}
  >
  > When you `use Backpex.LiveResource`, the `Backpex.LiveResource` module will set `@behavior Backpex.LiveResource`. Additionally it will create a LiveView based on the given configuration in order to create fully functional index, show, new and edit views for a resource. It will also insert fallback functions that can be overridden.

  ## Define a resource

  To explain configuration settings we created an event schema with a corresponding `EventLive` configuration file.

      defmodule MyAppWeb.EventLive do
        alias MyApp.Event

        use Backpex.LiveResource,
          layout: {MyAppWeb.LayoutView, :admin}, # Specify the layout you created in the step before
          schema: Event, # Schema of the resource
          repo: MyApp.Repo, # Ecto repository
          update_changeset: &Event.update_changeset/3, # Changeset to be used for update queries
          create_changeset: &Event.create_changeset/3,  # Changeset to be used for create queries
          pubsub: Demo.PubSub, # PubSub name of the project.
          topic: "events", # The topic for PubSub
          event_prefix: "event_", # The event prefix for Pubsub, to differentiate between events of different resources when subscribed to multiple resources
          fluid?: true # Optional to define if your resource should be rendered full width. Depends on the your [layout configuration](installation.md)

        # Singular name to displayed on the resource page
        @impl Backpex.LiveResource
        def singular_name(), do: "Event"

        # Plural name to displayed on the resource page
        @impl Backpex.LiveResource
        def plural_name(), do: "Events"

        # Field configurations
        # Here can configure which fields of the schema should be displayed on your dashboard.
        # Backpex provides certain field modules that may be used for displaying the field on index and form views.
        # You may define you own module or overwrite the render functions in this configuration (`render` for index views
        # and `render_form` for form views).
        @impl Backpex.LiveResource
        def fields do
          [
            # The title field of our event schema
            title: %{
              module: Backpex.Fields.Text,
              label: "Title"
            },
            # The location field of our event schema. It should not be displayed on `:edit` view.
            location: %{
              module: Backpex.Fields.Text,
              label: "Location",
              except: [:edit]
            },
            # The location field of our event schema. We use the Backpex URL module in order to make the url clickable.
            # This field is only displayed on `:index` view.
            url: %{
              module: Backpex.Fields.URL,
              label: "Url",
              only: [:index]
            },
            # The begins_at field of our event schema. We provide or own render function to display this field on index views.
            # The value can be extracted from the assigns.
            begins_at: %{
              module: Backpex.Fields.Date,
              label: "Begins At",
              render: fn assigns ->
                ~H"""
                <div class="text-red-500">
                  <%= @value %>
                </div>
                """
              end
            },
            # The ends_at field of our event schema. This field should not be sortable.
            ends_at: %{
              module: Backpex.Fields.Date,
              label: "Ends at"
            },
            # The published field of our url schema. We use the boolean field to display a switch button on edit views.
            published: %{
              module: Backpex.Fields.Boolean,
              label: "Published",
              sortable: false
            }
          ]
        end
      end

  ## Templates

  You are able to customize certain parts of Backpex. While you may use our app shell layout only you may also define functions to provide additional templates to be rendered on the resource LiveView or completely overwrite certain parts like the header or main content.

  See [render_resource_slot/3](Backpex.LiveResource.html#c:render_resource_slot/3) for supported positions.

  **Example:**
      # in your resource configuration file

      # to add content above main on index view
      def render_resource_slot(assigns, :index, :before_main), do: ~H"Hello World!"

  ## Item Query

  It is possible to manipulate the query when fetching resources for `index`, `show` and `edit` view by defining an `item_query` function.

  In all queries we define a `from` query with a named binding to fetch all existing resources on `index` view or a specific resource on `show` / `edit` view.
  After that, we call the `item_query` function. By default this returns the incoming query.

  The `item_query` function makes it easy to add custom query expressions.

  For example, you could filter posts by a published boolean on `index` view.

      # in your resource configuration file

      @impl Backpex.LiveResource
      def item_query(query, :index, _assigns) do
      query
      |> where([post], post.published)
      end

  In this example we also made use of the named binding. It's always the name of the provided schema in `snake_case`.
  It is recommended to build your `item_query` on top of the incoming query. Otherwise you will likely get binding errors.

  ## Authorize Actions

  Use `can?(_assigns, _action, _item)` function in you resource configuration to limit access to item actions
  (Actions: `:index`, `:new`, `:show`, `:edit`, `:delete`, `:your_item_action_key`, `:your_resource_action_key`).
  The function is not required and returns `true` by default.
  The item is `nil` for any action that does not require an item to be performed (`:index`, `:new`, `:your_resource_action_key`).

  **Examples:**
      # _item is nil for any action that does not require an item to be performed
      def can?(_assigns, :new, _item), do: false

      def can?(_assigns, :my_item_action, item), do: item.role == :admin

      def can?(assigns, :my_resource_action, nil), do: assigns.current_user == :admin

  > Note that item actions are always displayed if they are defined. If you want to remove item actions completely, you must restrict access to them with `can?/3` and remove the action with the `item_actions/1` function.

  ## Resource Actions

  You may define actions for certain resources in order to integrate complex processes into Backpex.

  Action routes are automatically generated when using the `live_resources` macro.

  For example you could add an invite process to your user resource as shown in the following.

  ```elixir
  defmodule MyAppWeb.Admin.Actions.Invite do
    use Backpex.ResourceAction

    import Ecto.Changeset

    @impl Backpex.ResourceAction
    def label, do: "Invite"

    @impl Backpex.ResourceAction
    def title, do: "Invite user"

    # you can reuse Backpex fields in the field definition
    @impl Backpex.ResourceAction
    def fields do
      [
        email: %{
          module: Backpex.Fields.Text,
          label: "Email",
          type: :string
        }
      ]
    end

    @required_fields ~w[email]a

    @impl Backpex.ResourceAction
    def changeset(change, attrs) do
      change
      |> cast(attrs, @required_fields)
      |> validate_required(@required_fields)
      |> validate_email(:email)
    end

    # your action to be performed
    @impl Backpex.ResourceAction
    def handle(_socket, params) do
      # Send mail

      # We suppose there was no error.
      if true do
        {:ok, "An email to #{params[:email]} was sent successfully."}
      else
        {:error, "An error occurred while sending an email to  #{params[:email]}!"}
      end
    end
  end
  ```

  ```elixir
  # in your resource configuration file

  # each action consists out of an unique id and the corresponding action module
  @impl Backpex.LiveResource
  def resource_actions() do
  [
    %{
      module: MyWebApp.Admin.ResourceActions.Invite,
      id: :invite
    }
  ]
  end
  ```

  ## Ordering

  You may provide an `init_order` option to specify how the initial index page is being ordered.

      # in your resource configuration file

      use Backpex.LiveResource,
        ...,
        init_order: %{by: :inserted_at, direction: :desc}

        # Routing

  ## Routing

  You are required to configure your router in order to point to the resources created in before steps.
  Make sure to use the `Backpex.InitAssigns` hook to ensure all Backpex assigns are applied to the LiveViews.

  You have to use the `Backpex.Router.live_resources/3` macro to generate routes for your resources.

      # MyAppWeb.Router

      import Backpex.Router

      scope "/admin", MyAppWeb do
      pipe_through :browser

      live_session :default, on_mount: Backpex.InitAssigns do
        live_resources("/events", EventLive)
      end

  In addition you have to use the `Backpex.Router.backpex_routes` macro. It will add some more routes at base scope. You can place this anywhere in your router.
  We will mainly use this routes to insert a `Backpex.CookieController`. We need it in order to save some user related settings (e.g. which columns on index view you selected to be active).

      # MyAppWeb.Router

      import Backpex.Router

      scope "/" do
        pipe_through :browser

        backpex_routes()
      end

  ## Searching

  You may flag fields as searchable. A search input will appear automatically on the resource index view.

      # in your resource configuration file
      @impl Backpex.LiveResource
      def fields do
        [
          %{
            ...,
            searchable: true
          }
        ]
      end

  For a custom placeholder, you can use the `elixir search_placeholder/0` callback.

      # in your resource configuration file
      @impl Backpex.LiveResource
      def search_placeholder, do: "This will be shown in the search input."

  In addition to basic searching, Backpex allows you to perform full-text searches on resources (see [Full-Text Search Guide](full_text_search.md)).

  ## Hooks

  You may define hooks that are called after their respective action. Those hooks are `on_item_created`, `on_item_updated` and `on_item_deleted`.
  These methods receive the socket and the corresponding item and are expected to return a socket.

      # in your resource configuration file
      @impl Backpex.LiveResource
      def on_item_created(socket, item) do
        # send an email on user creation
        socket
      end

  ## PubSub

  PubSub settings are required in order to support live updates.

      # in your resource configuration file
      use Backpex.LiveResource,
          ...,
          pubsub: Demo.PubSub, # PubSub name of the project.
          topic: "events", # The topic for PubSub
          event_prefix: "event_" # The event prefix for Pubsub, to differentiate between events of different resources when subscribed to multiple resources

  In addition you may react to `...deleted`, `...updated` and `...created` events via `handle_info`

      # in your resource configuration file
      @impl Phoenix.LiveView
      def handle_info({"event_created", item}, socket) do
        # make something in response to the event, for example show a toast to all users currently on the resource that an event has been created.
        {:noreply, socket}
      end

  ## Navigation

  You may define a custom navigation path that is called after the item is saved.
  The method receives the socket, the live action and the corresponding item and is expected to return a route path.

      # in your resource configuration file
      @impl Backpex.LiveResource
      def return_to(socket, assigns, _action, _item) do
        # return to user index after saving
        Routes.user_path(socket, :index)
      end

  ## Panels

  You are able to define panels to group certain fields together. Panels are displayed in the provided order.
  The `Backpex.LiveResource.panels/0` function has to return a keyword list with an identifier and label for each panel.
  You can move fields into panels with the `panel` field configuration that has to return the identifier of the corresponding panel. Fields without a panel are displayed in the `:default` panel. The `:default` panel has no label.

  > Note that a panel is not displayed when there are no fields in it.

      # in your resource configuration file
      @impl Backpex.LiveResource
      def panels do
        [
          contact: "Contact"
        ]
      end

      # in your fields list
      @impl Backpex.LiveResource
      def fields do
        [
          %{
            ...,
            panel: :contact
          }
        ]
      end

  ## Default values

  It is possible to assign default values to fields.

      # in your resource configuration file
      @impl Backpex.LiveResource
      def fields do
        [
          username: %{
            default: fn _assigns -> "Default Username" end
          }
        ]
      end

  > Note that default values are set when creating new resources only.

  ## Alignment

  You may align fields on index view. By default fields are aligned to the left.

  We currently support the following alignments: `:left`, `:center` and `:right`.

      # in your resource configuration file
      @impl Backpex.LiveResource
      def fields do
        [
          %{
            ...,
            align: :center
          }
        ]
      end

  In addition to field alignment, you can align the labels on form views (`index`, `edit`, `resource_action`) using the `align_label` field option.

  We currently support the following label orientations: `:top`, `:center` and `:bottom`.

      # in your resource configuration file
      @impl Backpex.LiveResource
      def fields do
        [
          %{
            ...,
            align_label: :top
          }
        ]
      end

  ## Fields Visibility

  You are able to change visibility of fields based on certain conditions (`assigns`).

  Imagine you want to implement a checkbox in order to toggle an input field (post likes). Initially, the input field should be visible when it has a certain value (post likes > 0).

      # in your resource configuration file
      @impl Backpex.LiveResource
      def fields do
        [
          # show_likes is a virtual field in the post schema
          show_likes: %{
            module: Backpex.Fields.Boolean,
            label: "Show likes",
            # initialize the button based on the likes value
            select: dynamic([post: p], fragment("? > 0", p.likes)),
          },
          likes: %{
            module: Backpex.Fields.Number,
            label: "Likes",
            # display the field based on the `show_likes` value
            # the value can be part of the changeset or item (when edit view is opened initially).
            visible: fn
              %{live_action: :new} = assigns ->
                Map.get(assigns.changeset.changes, :show_likes)

              %{live_action: :edit} = assigns ->
                Map.get(assigns.changeset.changes, :show_likes, Map.get(assigns.item, :show_likes, false))

              _assigns ->
                true
            end
          }
        ]
      end

  > Note that hidden fields are not exempt from validation by Backpex itself and the visible function is not executed on `:index`.

  In addition to `visible/1`, we provide a `can?1` function that you can use to determine the visibility of a field.
  It can also be used on `:index` and takes the `assigns` as a parameter.

      # in your resource configuration file
      inserted_at: %{
        module: Backpex.Fields.DateTime,
        label: "Created At",
        can?: fn
          %{live_action: :show} = _assigns ->
            true

          _assigns ->
            false
        end
      }

  ## Tooltips

  We support tooltips via [daisyUI](https://daisyui.com/components/tooltip/).

  ## Index Editable

  A small number of fields support index editable. These fields can be edited inline on the index view.

  You must enable index editable for a field.

      # in your resource configuration file
      def fields do
        [
          name: %{
            module: Backpex.Fields.Text,
            label: "Name",
            index_editable: true
          }
        ]
      end

  Currently supported by the following fields:
  - `Backpex.Fields.Number`
  - `Backpex.Fields.Select`
  - `Backpex.Fields.Text`

  > Note you can add index editable support to your custom fields by defining the `render_index_form/1` function and enabling index editable for your field.
  '''

  alias Backpex.Resource

  @doc """
  A list of [resource_actions](resource_actions.html) that may be performed on the given resource.
  """
  @callback resource_actions() :: list()

  @doc """
  A list of [item_actions](item_actions.html) that may be performed on (selected) items.
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
  @callback item_query(query :: Ecto.Query.t(), live_action :: atom(), assigns :: map()) ::
              Ecto.Query.t()

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
  A optional keyword list of [filters](filters.html) to be used on the index view.
  """
  @callback filters() :: keyword()

  @doc """
  A optional keyword list of [filters](filters.html) to be used on the index view.
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
  Uses LiveResource in the current module to make it a LiveResource.

      use Backpex.LiveResource,
        layout: {MyAppWeb.LayoutView, :admin},
        schema: MyApp.User,
        repo: MyApp.Repo,
        update_changeset: &MyApp.User.update_changeset/3,
        create_changeset: &MyApp.User.create_changeset/3

  ## Options

    * `:layout` - Layout to be used by the LiveResource.
    * `:schema` - Schema for the resource.
    * `:repo` - Ecto repo that will be used to perform CRUD operations for the given schema.
    * `:update_changeset` - Changeset to use when updating items. Additional metadata is passed as a keyword list via the third parameter.

      The list of metadata:
      - `:assigns` - the assigns
      - `:target` - the name of the `form` target that triggered the changeset call. Default to `nil` if the call was not triggered by a form field.
    * `:create_changeset` - Changeset to use when creating items. Additional metadata is passed as a keyword list via the third parameter.

      The list of metadata:
      - `:assigns` - the assigns
      - `:target` - the name of the `form` target that triggered the changeset call. Default to `nil` if the call was not triggered by a form field.
    * `:pubsub` - PubSub name of the project.
    * `:topic` - The topic for PubSub.
    * `:event_prefix` - The event prefix for Pubsub, to differentiate between events of different resources when subscribed to multiple resources.
    * `:per_page_options` - The page size numbers you can choose from.
      Defaults to `[15, 50, 100]`.
    * `:per_page_default` - The default page size number.
      Defaults to the first element of the `per_page_options` list.
    * `:init_order` - Order that will be used when no other order options are given.
      Defaults to `%{by: :id, direction: :asc}`.
  """
  defmacro __using__(opts) do
    layout = Keyword.fetch!(opts, :layout)
    schema = Keyword.fetch!(opts, :schema)
    repo = Keyword.fetch!(opts, :repo)

    pubsub = Keyword.get(opts, :pubsub)
    topic = Keyword.get(opts, :topic)
    event_prefix = Keyword.get(opts, :event_prefix)

    update_changeset = Keyword.fetch!(opts, :update_changeset)
    create_changeset = Keyword.fetch!(opts, :create_changeset)

    per_page_options = Keyword.get(opts, :per_page_options, [15, 50, 100])
    per_page_default = Keyword.get(opts, :per_page_default, hd(per_page_options))

    init_order = Keyword.get(opts, :init_order, Macro.escape(%{by: :id, direction: :asc}))

    fluid? = Keyword.get(opts, :fluid?, false)

    full_text_search = Keyword.get(opts, :full_text_search)

    quote do
      @before_compile Backpex.LiveResource
      @behaviour Backpex.LiveResource

      use BackpexWeb, :html
      use Phoenix.LiveView, layout: unquote(layout)

      import Backpex.HTML.Resource
      import Backpex.LiveResource
      import Phoenix.LiveView.Helpers
      import Ecto.Query

      alias Backpex.Resource
      alias Backpex.ResourceAction
      alias Backpex.Router

      require Logger

      @permitted_order_directions ~w(asc desc)a
      @empty_filter_key :empty_filter

      @impl Phoenix.LiveView
      def mount(params, session, socket) do
        pubsub = pubsub_settings(unquote(pubsub), unquote(topic), unquote(event_prefix))

        maybe_subscribe(socket, pubsub)

        socket =
          socket
          |> assign(:schema, unquote(schema))
          |> assign(:repo, unquote(repo))
          |> assign(:pubsub, pubsub)
          |> assign(:singular_name, singular_name())
          |> assign(:plural_name, plural_name())
          |> assign(:search_placeholder, search_placeholder())
          |> assign(:panels, panels())
          |> assign(:live_resource, __MODULE__)
          |> assign(:fluid?, unquote(fluid?))
          |> assign(:full_text_search, unquote(full_text_search))
          |> assign_active_fields(session)
          |> assign_metrics_visibility(session)
          |> assign_filters_changed_status(params)

        {:ok, socket}
      end

      defp assign_active_fields(socket, session) do
        fields = filtered_fields_by_action(fields(), socket.assigns, :index)
        saved_fields = get_in(session, ["backpex", "column_toggle", "#{__MODULE__}"]) || %{}

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
        |> assign(
          :page_title,
          socket.assigns.plural_name
        )
        |> apply_index()
        |> assign(:item, nil)
      end

      def apply_action(socket, :edit) do
        %{
          assigns: %{live_action: live_action, singular_name: singular_name, params: params} = assigns
        } = socket

        fields = filtered_fields_by_action(fields(), assigns, :edit)

        item =
          Resource.get(
            assigns,
            &item_query(&1, live_action, assigns),
            fields,
            params["backpex_id"]
          )

        unless can?(socket.assigns, :edit, item, __MODULE__),
          do: raise(Backpex.ForbiddenError)

        socket
        |> assign(:fields, fields)
        |> assign(:changeset_function, unquote(update_changeset))
        |> assign(
          :page_title,
          Backpex.translate({"Edit %{resource}", %{resource: singular_name}})
        )
        |> assign(:item, item)
        |> assign_changeset(fields)
      end

      def apply_action(socket, :show) do
        %{
          assigns: %{live_action: live_action, singular_name: singular_name, params: params} = assigns
        } = socket

        fields = filtered_fields_by_action(fields(), assigns, :show)

        item =
          Resource.get(
            assigns,
            &item_query(&1, live_action, assigns),
            fields,
            params["backpex_id"]
          )

        unless can?(assigns, :show, item, __MODULE__),
          do: raise(Backpex.ForbiddenError)

        socket
        |> assign(
          :page_title,
          singular_name
        )
        |> assign(:fields, fields)
        |> assign(:item, item)
        |> apply_show_return_to(item)
      end

      def apply_action(socket, :new) do
        %{assigns: %{schema: schema, singular_name: singular_name} = assigns} = socket

        unless can?(assigns, :new, nil, __MODULE__),
          do: raise(Backpex.ForbiddenError)

        fields = filtered_fields_by_action(fields(), assigns, :new)
        empty_item = schema.__struct__()

        socket
        |> assign(:changeset_function, unquote(create_changeset))
        |> assign(
          :page_title,
          Backpex.translate({"New %{resource}", %{resource: singular_name}})
        )
        |> assign(:fields, fields)
        |> assign(:item, empty_item)
        |> assign_changeset(fields)
      end

      def apply_action(socket, :resource_action) do
        id = String.to_existing_atom(socket.assigns.params["backpex_id"])
        action = resource_actions()[id]

        unless can?(socket.assigns, id, nil, __MODULE__),
          do: raise(Backpex.ForbiddenError)

        socket =
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
        item_actions = item_actions(default_item_actions())
        assign(socket, :item_actions, item_actions)
      end

      def apply_item_actions(socket, _action), do: socket

      defp apply_index_return_to(socket) do
        %{assigns: %{params: params, query_options: query_options} = assigns} = socket

        socket
        |> assign(
          :return_to,
          Router.get_path(socket, __MODULE__, params, :index, query_options)
        )
      end

      defp apply_show_return_to(socket, item) do
        socket
        |> assign(
          :return_to,
          Router.get_path(socket, __MODULE__, socket.assigns.params, :show, item)
        )
      end

      defp apply_index(socket) do
        %{
          assigns:
            %{
              repo: repo,
              schema: schema,
              live_action: live_action,
              params: params
            } = assigns
        } = socket

        unless can?(assigns, :index, nil, __MODULE__),
          do: raise(Backpex.ForbiddenError)

        fields = filtered_fields_by_action(fields(), assigns, :index)

        per_page_options = unquote(per_page_options)
        per_page_default = unquote(per_page_default)
        init_order = unquote(init_order)

        filters = Backpex.LiveResource.get_active_filters(__MODULE__, assigns)
        valid_filter_params = Backpex.LiveResource.get_valid_filters_from_params(params, filters, @empty_filter_key)

        item_count =
          Resource.count(
            assigns,
            &item_query(&1, live_action, assigns),
            fields,
            search_options(params, fields, schema),
            filter_options(valid_filter_params, filters)
          )

        per_page =
          params
          |> parse_integer("per_page", per_page_default)
          |> value_in_permitted_or_default(per_page_options, per_page_default)

        total_pages = calculate_total_pages(item_count, per_page)
        page = params |> parse_integer("page", 1) |> validate_page(total_pages)

        page_options = %{page: page, per_page: per_page}

        order_options = order_options_by_params(params, fields, init_order, @permitted_order_directions)

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
        |> assign(:resource_actions, resource_actions())
        |> assign(:action_to_confirm, nil)
        |> assign(:selected_items, [])
        |> assign(:select_all, false)
        |> assign(:fields, fields)
        |> assign(:changeset_function, unquote(update_changeset))
        |> maybe_redirect_to_default_filters()
        |> assign_items(init_order)
        |> maybe_assign_metrics()
        |> apply_index_return_to()
      end

      defp assign_changeset(socket, fields) do
        %{
          assigns:
            %{
              item: item,
              changeset_function: changeset_function,
              live_action: live_action
            } = assigns
        } = socket

        changeset =
          Backpex.LiveResource.call_changeset_function(
            item,
            changeset_function,
            default_attrs(live_action, fields, assigns),
            assigns
          )

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
          assigns:
            %{
              query_options: query_options,
              params: params,
              filters: filters
            } = assigns
        } = socket

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
          to = Router.get_path(socket, __MODULE__, params, :index, options)
          push_redirect(socket, to: to)
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

      defp maybe_put_search(query_options, params), do: query_options

      def assign_items(socket, init_order) do
        assign(socket, :items, list_items(socket, init_order, &item_query/3))
      end

      defp maybe_assign_metrics(socket) do
        %{
          assigns:
            %{
              repo: repo,
              schema: schema,
              live_action: live_action,
              live_resource: live_resource,
              params: params,
              fields: fields,
              query_options: query_options,
              metric_visibility: metric_visibility
            } = assigns
        } = socket

        filters = Backpex.LiveResource.get_active_filters(__MODULE__, assigns)

        query =
          Resource.list_query(
            assigns,
            &item_query(&1, live_action, assigns),
            fields,
            search: search_options(query_options, fields, schema),
            filters: filter_options(query_options, filters)
          )

        metrics =
          metrics()
          |> Backpex.Metric.load_data_for_visible(
            metric_visibility,
            live_resource,
            query,
            repo
          )

        socket
        |> assign(metrics: metrics)
      end

      @impl Phoenix.LiveView
      def handle_event("close-modal", _params, socket) do
        socket =
          socket
          |> push_patch(to: socket.assigns.return_to)

        {:noreply, socket}
      end

      @impl Phoenix.LiveView
      def handle_event("item-action", %{"action-key" => key, "item-id" => item_id}, socket) do
        item = Enum.find(socket.assigns.items, fn item -> item.id == item_id end)

        socket
        |> assign(selected_items: [item])
        |> maybe_handle_item_action(key)
      end

      def handle_event("item-action", %{"action-key" => key}, socket) do
        maybe_handle_item_action(socket, key)
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
        {:noreply, assign(socket, action_to_confirm: Map.put(action, :key, key))}
      end

      defp handle_item_action(socket, action, key, items) do
        items = Enum.filter(items, fn item -> can?(socket.assigns, key, item, __MODULE__) end)

        socket
        |> assign(action_to_confirm: nil)
        |> assign(selected_items: [])
        |> assign(select_all: false)
        |> action.module.handle(items, %{})
      end

      @impl Phoenix.LiveView
      def handle_event(
            "select-page-size",
            %{"select_per_page" => %{"per_page" => per_page}},
            socket
          ) do
        %{assigns: %{query_options: query_options, params: params} = assigns} = socket

        per_page = String.to_integer(per_page)

        to =
          Router.get_path(
            socket,
            __MODULE__,
            params,
            :index,
            Map.merge(query_options, %{per_page: per_page})
          )

        socket = push_patch(socket, to: to, replace: true)

        {:noreply, socket}
      end

      @impl Phoenix.LiveView
      def handle_event(
            "index-search",
            %{"index_search" => %{"search_input" => search_input}},
            socket
          ) do
        %{assigns: %{query_options: query_options, params: params} = assigns} = socket

        to =
          Router.get_path(
            socket,
            __MODULE__,
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
            __MODULE__,
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
        %{assigns: %{query_options: query_options, params: params, live_resource: live_resource} = assigns} = socket

        new_query_options =
          Map.put(
            query_options,
            :filters,
            Map.get(query_options, :filters, %{})
            |> Map.delete(field)
            |> Backpex.LiveResource.maybe_put_empty_filter(@empty_filter_key)
          )

        to = Router.get_path(socket, __MODULE__, params, :index, new_query_options)

        socket =
          push_patch(socket, to: to)
          |> assign(params: Map.merge(params, new_query_options))
          |> assign(query_options: new_query_options)
          |> assign(filters_changed: true)

        {:noreply, socket}
      end

      @impl Phoenix.LiveView
      def handle_event("filter-preset-selected", %{"field" => field, "preset-index" => preset_index} = params, socket) do
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
            __MODULE__,
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
        item = Enum.find(socket.assigns.items, fn item -> item.id == id end)

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
      def handle_info({"backpex:" <> unquote(event_prefix) <> "created", item}, socket)
          when socket.assigns.live_action in [:index, :resource_action] do
        {:noreply, refresh_items(socket)}
      end

      @impl Phoenix.LiveView
      def handle_info({"backpex:" <> unquote(event_prefix) <> "deleted", item}, socket)
          when socket.assigns.live_action in [:index, :resource_action] do
        if Enum.filter(socket.assigns.items, &(&1.id == item.id)) != [] do
          {:noreply, refresh_items(socket)}
        else
          {:noreply, socket}
        end
      end

      @impl Phoenix.LiveView
      def handle_info({"backpex:" <> unquote(event_prefix) <> "updated", item}, socket)
          when socket.assigns.live_action in [:index, :resource_action, :show] do
        {:noreply, update_item(socket, item)}
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

      def get_empty_filter_key, do: @empty_filter_key

      defp update_item(socket, %{id: id} = _item) do
        %{assigns: %{live_action: live_action} = assigns} = socket

        fields = filtered_fields_by_action(fields(), assigns, :show)
        item = Resource.get(assigns, &item_query(&1, live_action, assigns), fields, id)

        socket =
          cond do
            live_action in [:index, :resource_action] ->
              items = Enum.map(socket.assigns.items, &if(&1.id == id, do: item, else: &1))

              assign(socket, :items, items)

            live_action == :show ->
              assign(socket, :item, item)

            true ->
              socket
          end

        socket
      end

      defp refresh_items(socket) do
        %{
          assigns:
            %{
              schema: schema,
              live_action: live_action,
              params: params,
              fields: fields,
              query_options: query_options,
              init_order: init_order
            } = assigns
        } = socket

        filters = Backpex.LiveResource.get_active_filters(__MODULE__, assigns)
        valid_filter_params = Backpex.LiveResource.get_valid_filters_from_params(params, filters, @empty_filter_key)

        item_count =
          Resource.count(
            assigns,
            &item_query(&1, live_action, assigns),
            fields,
            search_options(params, fields, schema),
            filter_options(valid_filter_params, filters)
          )

        %{page: page, per_page: per_page} = query_options
        total_pages = calculate_total_pages(item_count, per_page)
        new_query_options = Map.put(query_options, :page, validate_page(page, total_pages))

        socket
        |> assign(:item_count, item_count)
        |> assign(:total_pages, total_pages)
        |> assign(:query_options, new_query_options)
        |> assign_items(init_order)
        |> maybe_assign_metrics()
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
      def fields, do: []

      @impl Backpex.LiveResource
      def filters, do: []

      @impl Backpex.LiveResource
      def filters(_assigns), do: filters()

      @impl Backpex.LiveResource
      def resource_actions, do: []

      @impl Backpex.LiveResource
      def item_actions(default_actions), do: default_actions

      defoverridable can?: 3, fields: 0, filters: 0, filters: 1, resource_actions: 0, item_actions: 1
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      import Backpex.HTML.Layout
      import Backpex.HTML.Resource
      alias Backpex.Router

      @impl Phoenix.LiveView
      def handle_info(_message, socket) do
        {:noreply, socket}
      end

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
        Map.get(assigns, :return_to, Router.get_path(socket, __MODULE__, %{}, :index))
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
            :if={Backpex.LiveResource.can?(assigns, :edit, @item, @live_resource)}
            class="tooltip"
            data-tip={Backpex.translate("Edit")}
            aria-label={Backpex.translate("Edit")}
            patch={Router.get_path(@socket, @live_resource, @params, :edit, @item)}
          >
            <Heroicons.pencil_square class="h-6 w-6 cursor-pointer transition duration-75 hover:scale-110 hover:text-blue-600" />
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
          <%= Backpex.translate({"New %{resource}", %{resource: @singular_name}}) %>
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

  @doc """
  Returns pubsub settings based on configuration.
  """
  def pubsub_settings(false, _topic, _event_prefix), do: false

  def pubsub_settings(pubsub, topic, event_prefix) do
    %{name: pubsub, topic: topic, event_prefix: event_prefix}
  end

  @doc """
  Maybe subscribes to pubsub.
  """
  def maybe_subscribe(_socket, false), do: :ok

  def maybe_subscribe(socket, %{name: name, topic: topic}) do
    if Phoenix.LiveView.connected?(socket) do
      Phoenix.PubSub.subscribe(name, topic)
    end
  end

  @doc """
  Returns order options by params.

  ## Examples

      iex> Backpex.LiveResource.order_options_by_params(%{"order_by" => "field", "order_direction" => "asc"}, [field: %{}], %{by: :id, direction: :asc}, [:asc, :desc])
      %{order_by: :field, order_direction: :asc}
      iex> Backpex.LiveResource.order_options_by_params(%{}, [field: %{}], %{by: :id, direction: :desc}, [:asc, :desc])
      %{order_by: :id, order_direction: :desc}
      iex> Backpex.LiveResource.order_options_by_params(%{"order_by" => "field", "order_direction" => "asc"}, [field: %{orderable: false}], %{by: :id, direction: :asc}, [:asc, :desc])
      %{order_by: :id, order_direction: :asc}
  """
  def order_options_by_params(params, fields, init_order, permitted_order_directions) do
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
  List all items for current page with filters and search applied.
  """
  def list_items(socket, init_order, item_query) do
    %{
      assigns:
        %{
          schema: schema,
          fields: fields,
          live_action: live_action,
          filters: filters,
          query_options: query_options
        } = assigns
    } = socket

    field = Enum.find(fields, fn {name, _field_options} -> name == query_options.order_by end)

    order =
      if orderable?(field) do
        {_field_name, field_options} = field

        %{
          by: field_options.module.display_field(field),
          schema: field_options.module.schema(field, schema),
          direction: query_options.order_direction
        }
      else
        init_order
        |> Map.put(:schema, schema)
      end

    Resource.list(
      assigns,
      &item_query.(&1, live_action, assigns),
      fields,
      order: order,
      pagination: %{page: query_options.page, size: query_options.per_page},
      search: search_options(query_options, fields, schema),
      filters: filter_options(query_options, filters)
    )
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
  Checks whether user is allowed to perform provided action or not
  """
  def can?(assigns, action, item, module) do
    module.can?(assigns, action, item)
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

  @doc """
  Calls the changeset function with the given change and target.
  """
  def call_changeset_function(item, changeset_function, change, assigns, target \\ nil) do
    metadata =
      Keyword.new()
      |> Keyword.put(:assigns, assigns)
      |> Keyword.put(:target, target)

    changeset_function.(item, change, metadata)
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
  def get_filter_options(module, query_options) do
    query_options
    |> Map.get(:filters, %{})
    |> Map.drop([Atom.to_string(module.get_empty_filter_key())])
  end

  @doc """
  Returns list of active filters.
  """
  def get_active_filters(module, assigns) do
    filters = module.filters(assigns)

    Enum.filter(filters, fn {key, option} ->
      module.get_empty_filter_key() != key and option.module.can?(assigns)
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
