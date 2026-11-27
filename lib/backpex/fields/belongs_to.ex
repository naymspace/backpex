# quokka:skip-module-directive-reordering
defmodule Backpex.Fields.BelongsTo do
  @config_schema [
    display_field: [
      doc: "The field of the relation to be used for searching, ordering and displaying values.",
      type: :atom,
      required: true
    ],
    display_field_form: [
      doc: "Field to be used to display form values.",
      type: :atom
    ],
    live_resource: [
      doc: "The live resource of the association. Used to generate links navigating to the association.",
      type: :atom
    ],
    options_query: [
      doc: """
      Manipulates the list of available options in the select.

      The form and the index form of the field also check the submitted value against the options query: they save an
      option or no option, and the form also the value the item already has. The check only runs for a field that is
      part of the form and not readonly, so the options query is no replacement for a check in your changeset.

      Defaults to `fn (query, _field) -> query end` which returns all entries.
      """,
      type: {:fun, 2}
    ],
    prompt: [
      doc: "The text to be displayed when no option is selected or function that receives the assigns.",
      type: {:or, [:string, {:fun, 1}]}
    ],
    searchable_options: [
      doc: """
      Whether the select has a search input that filters the options. Ignored with `:query_limit`, as the select then
      always has a search input.
      """,
      type: :boolean,
      default: false
    ],
    query_limit: [
      doc: """
      The number of options the select loads at a time. With a limit, the select searches the options on the server
      and loads further options with "Show more", instead of loading every option of the `options_query`. Set it for a
      relation with many records, e.g. users.

      The search matches the `display_field_form`, or the `select` expression of the field if it has one and no
      `display_field_form`, so these have to be columns of the related schema or a `select` expression.

      Defaults to `nil`, which loads every option.
      """,
      type: {:or, [:pos_integer, nil]},
      default: nil
    ],
    debounce: [
      doc: "Timeout value (in milliseconds), \"blur\" or function that receives the assigns.",
      type: {:or, [:pos_integer, :string, {:fun, 1}]}
    ],
    throttle: [
      doc: "Timeout value (in milliseconds) or function that receives the assigns.",
      type: {:or, [:pos_integer, {:fun, 1}]}
    ]
  ]

  @moduledoc """
  A field for handling a `belongs_to` relation.

  The form and the index form render a `Backpex.HTML.Combobox.combobox/1` with all options of the `options_query`. The
  `prompt` is shown while no option is selected, and a field with a `prompt` has a button that clears the selection.
  Without a `prompt` the select has no empty state, like a native select: it selects its first option while the item
  has no value.

  For a relation with many records, set `query_limit`: the select then loads that many options at a time, searches
  them on the server and loads further options with "Show more". The current value is shown even if it is on no loaded
  page.

  ## Field-specific options

  See `Backpex.Field` for general field options.

  #{NimbleOptions.docs(@config_schema)}

  ## Example

      @impl Backpex.LiveResource
      def fields do
      [
        user: %{
          module: Backpex.Fields.BelongsTo,
          label: "Username",
          display_field: :username,
          options_query: &where(&1, [user], user.role == :admin),
          query_limit: 20,
          live_resource: DemoWeb.UserLive
        }
      ]
      end
  """
  use Backpex.Field, config_schema: @config_schema
  import Ecto.Query
  alias Backpex.Adapters.Ecto, as: EctoAdapter
  alias Backpex.Authorization
  alias Backpex.Fields.OptionsQuery
  alias Backpex.HTML.Combobox
  alias Backpex.Router

  require Backpex

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    %{name: name, field: field} = assigns
    schema = assigns.live_resource.adapter_config(:schema)
    %{queryable: queryable, owner_key: owner_key, related_key: related_key} = schema.__schema__(:association, name)

    display_field = display_field(field)
    display_field_form = display_field_form(field, display_field)

    socket
    |> assign(assigns)
    |> assign(queryable: queryable)
    |> assign(owner_key: owner_key)
    |> assign(related_key: related_key)
    |> assign(display_field: display_field)
    |> assign(display_field_form: display_field_form)
    |> assign_server_options()
    |> ok()
  end

  @impl Backpex.Field
  def render_value(%{value: value} = assigns) when is_nil(value) do
    ~H"""
    <p class={@live_action in [:index, :resource_action] && "truncate"}>
      {HTML.pretty_value(nil)}
    </p>
    """
  end

  @impl Backpex.Field
  def render_value(assigns) do
    %{value: value, display_field: display_field} = assigns

    assigns =
      assigns
      |> assign(:display_text, Map.get(value, display_field))
      |> assign_link()

    ~H"""
    <div class={[@live_action in [:index, :resource_action] && "truncate"]}>
      <%= if @link do %>
        <.link navigate={@link} class={[@live_action in [:index, :resource_action] && "truncate", "hover:underline"]}>
          {@display_text}
        </.link>
      <% else %>
        <p class={@live_action in [:index, :resource_action] && "truncate"}>
          {HTML.pretty_value(@display_text)}
        </p>
      <% end %>
    </div>
    """
  end

  @impl Backpex.Field
  def render_form(assigns) do
    %{field_options: field_options, owner_key: owner_key} = assigns

    assigns =
      assigns
      |> assign_form_select()
      |> assign(:owner_key, owner_key)
      |> assign(:label_id, "#{assigns.form[owner_key].id}-label")
      |> assign_prompt(field_options)

    ~H"""
    <div>
      <Layout.field_container>
        <:label :if={not @hide_label} align={Backpex.Field.align_label(@field_options, assigns)}>
          <Layout.input_label id={@label_id} for={"#{@form[@owner_key].id}-trigger"} text={@field_options[:label]} />
        </:label>
        <Combobox.combobox
          field={@form[@owner_key]}
          value={selected_value(@form[@owner_key].value, @default_option, @prompt)}
          options={@options}
          selected_options={@selected_options}
          on_search={@on_search}
          placeholder={@prompt}
          clearable={@prompt != nil}
          searchable={@searchable}
          readonly={@readonly}
          translate_error_fun={Backpex.Field.translate_error_fun(@field_options, assigns)}
          help_text={Backpex.Field.help_text(@field_options, assigns)}
          live_resource={@live_resource}
          phx-target={@search_target}
          phx-debounce={Backpex.Field.debounce(@field_options, assigns)}
          phx-throttle={Backpex.Field.throttle(@field_options, assigns)}
          {Backpex.Field.label_attrs(assigns, @label_id)}
        >
          <:footer :if={@show_more}>
            <.show_more live_resource={@live_resource} target={@search_target} />
          </:footer>
        </Combobox.combobox>
      </Layout.field_container>
    </div>
    """
  end

  @impl Backpex.Field
  def index_assigns({name, field_options} = field, items, assigns) do
    if Backpex.Field.index_editable_enabled?(field_options, assigns) do
      %{live_resource: live_resource} = assigns
      association = live_resource.adapter_config(:schema).__schema__(:association, name)
      %{queryable: queryable, related_key: related_key, owner_key: owner_key} = association

      field_assigns =
        Map.merge(assigns, %{
          name: name,
          field: field,
          field_options: field_options,
          queryable: queryable,
          related_key: related_key,
          display_field_form: display_field_form(field, display_field(field))
        })

      options_queries =
        Map.new(items, fn item ->
          item_assigns = Map.merge(field_assigns, %{item: item, value: Map.get(item, name)})
          {LiveResource.primary_value(item, live_resource), {options_query(item_assigns), Map.get(item, owner_key)}}
        end)

      index_form_options(options_queries, field_options, options_opts(field_assigns))
    else
      %{}
    end
  end

  # Loads the options of each distinct options query once. With `query_limit`, the first page of the options and the
  # options of the values of the rows, as these may be on no loaded page.
  defp index_form_options(options_queries, %{query_limit: limit}, opts) when is_integer(limit) do
    pages =
      options_queries
      |> Map.values()
      |> Enum.group_by(fn {query, _value} -> query end, fn {_query, value} -> value end)
      |> Map.new(fn {query, values} ->
        {options, show_more} = OptionsQuery.page(query, [limit: limit], opts)
        values = values |> Enum.reject(&is_nil/1) |> Enum.uniq()
        value_options = if values == [], do: [], else: OptionsQuery.list(query, [ids: values], opts)

        {query, %{options: options, show_more: show_more, value_options: options ++ value_options}}
      end)

    index_form_pages =
      Map.new(options_queries, fn {key, {query, value}} ->
        %{options: options, show_more: show_more, value_options: value_options} = Map.fetch!(pages, query)

        {key, %{options: options, show_more: show_more, selected_option: find_option(value_options, value)}}
      end)

    %{index_form_pages: index_form_pages}
  end

  defp index_form_options(options_queries, _field_options, opts) do
    options_by_query =
      options_queries
      |> Map.values()
      |> Enum.map(fn {query, _value} -> query end)
      |> Enum.uniq()
      |> Map.new(&{&1, OptionsQuery.list(&1, [], opts)})

    %{index_form_options: Map.new(options_queries, fn {key, {query, _value}} -> {key, options_by_query[query]} end)}
  end

  @impl Backpex.Field
  def render_index_form(assigns) do
    assigns =
      assigns
      |> assign_index_form_select()
      |> Backpex.Field.assign_index_form()
      |> assign_prompt(assigns.field_options)

    ~H"""
    <div>
      <BackpexForm.index_form form={@form} name={@name} item={@item} live_resource={@live_resource} class="relative">
        <Combobox.combobox
          id={"index-form-input-#{@name}-#{LiveResource.primary_value(@item, @live_resource)}"}
          field={@form[:value]}
          options={@options}
          selected_options={@selected_options}
          on_search={@on_search}
          placeholder={@prompt}
          clearable={@prompt != nil}
          searchable={@searchable}
          value={
            selected_value(
              if(@valid, do: @value && Map.get(@value, @related_key), else: @form[:value].value),
              @default_option,
              @prompt
            )
          }
          size="sm"
          class="min-w-max"
          input_class={[
            "input min-w-32 max-w-80 h-auto min-h-(--size) w-max py-1",
            @valid && "not-hover:input-ghost",
            !@valid && "input-error bg-error/10"
          ]}
          disabled={@readonly}
          hide_errors
          live_resource={@live_resource}
          phx-target={@search_target}
          aria-label={@field_options[:label]}
        >
          <:footer :if={@show_more}>
            <.show_more live_resource={@live_resource} target={@search_target} />
          </:footer>
        </Combobox.combobox>
      </BackpexForm.index_form>
    </div>
    """
  end

  attr :live_resource, :atom, required: true
  attr :target, :any, required: true

  defp show_more(assigns) do
    ~H"""
    <button type="button" phx-click="show-more" phx-target={@target} class="link block text-sm">
      {Backpex.__("Show more", @live_resource)}
    </button>
    """
  end

  # The combobox pushes the search with the text of its search input, and an empty search when its popup closes.
  @impl Phoenix.LiveComponent
  def handle_event("search", %{"query" => query}, socket) when is_binary(query) do
    socket
    |> assign(search_input: query, offset: 0)
    |> assign_options()
    |> noreply()
  end

  def handle_event("search", _params, socket), do: noreply(socket)

  @impl Phoenix.LiveComponent
  def handle_event("show-more", _params, socket) do
    %{assigns: %{field_options: field_options, offset: offset, options: options}} = socket

    socket
    |> assign(:offset, offset + field_options[:query_limit])
    |> assign_options(options)
    |> noreply()
  end

  @impl Backpex.Field
  def index_editable_change({name, _field_options} = field, value, assigns) do
    association = assigns.live_resource.adapter_config(:schema).__schema__(:association, name)

    if option?(field, association, value, assigns), do: %{association.owner_key => value}, else: :error
  end

  # The value comes from the client, so the form saves only an option of the select, no option, or the value the item
  # already has. The item may keep a value that is no longer an option, e.g. an author who was deleted since.
  @impl Backpex.Field
  def before_changeset(changeset, attrs, _metadata, _repo, {name, _field_options} = field, assigns) do
    association = assigns.live_resource.adapter_config(:schema).__schema__(:association, name)
    %{owner_key: owner_key} = association

    with {:ok, value} <- Map.fetch(attrs, Atom.to_string(owner_key)),
         false <- current_value?(changeset.data, owner_key, value),
         false <- option?(field, association, value, OptionsQuery.put_submitted_form(assigns, changeset, attrs)) do
      # Ecto's message and metadata for a value outside the allowed ones, so the error translation of the app applies.
      Ecto.Changeset.add_error(changeset, owner_key, "is invalid", validation: :inclusion)
    else
      _valid -> changeset
    end
  end

  defp current_value?(%{__struct__: schema} = data, owner_key, value) do
    type = schema.__schema__(:type, owner_key)

    Ecto.Type.cast(type, value) == {:ok, Map.get(data, owner_key)}
  end

  # The item of a resource action is a map by default. It has no current value, so the value has to be an option.
  defp current_value?(_data, _owner_key, _value), do: false

  # The value comes from the client, so only an option of the select, or no option, is saved.
  defp option?(_field, _association, value, _assigns) when value in [nil, ""], do: true

  defp option?({_name, field_options} = field, association, value, assigns) do
    %{queryable: queryable, related_key: related_key} = association

    case cast_value(queryable, related_key, value) do
      {:ok, id} ->
        assigns
        |> Map.merge(%{
          field: field,
          queryable: queryable,
          field_options: field_options,
          display_field_form: display_field_form(field, display_field(field))
        })
        |> options_query()
        |> OptionsQuery.with_ids(queryable, related_key, [id])
        |> assigns.live_resource.adapter_config(:repo).exists?()

      _error ->
        false
    end
  end

  defp cast_value(queryable, key, value), do: queryable.__schema__(:type, key) |> Ecto.Type.cast(value)

  @impl Backpex.Field
  def display_field({_name, field_options}) do
    Map.get(field_options, :display_field)
  end

  @impl Backpex.Field
  def schema({name, _field_options}, schema) do
    schema.__schema__(:association, name)
    |> Map.get(:queryable)
  end

  @impl Backpex.Field
  def association?(_field), do: true

  # The select submits the foreign key of the association.
  @impl Backpex.Field
  def param_keys({name, _field_options}, assigns) do
    %{owner_key: owner_key} = assigns.live_resource.adapter_config(:schema).__schema__(:association, name)

    [Atom.to_string(owner_key)]
  end

  # Like a native select, a select without a prompt has no empty state: without a value it selects its first option.
  defp selected_value(value, {_label, first} = _default_option, nil = _prompt) when value in [nil, ""], do: first
  defp selected_value(value, _default_option, _prompt), do: value

  defp display_field_form({_name, field_options} = _field, display_field) do
    Map.get(field_options, :display_field_form, display_field)
  end

  # The root binding is named like the binding of the relation in the index query, so a `select` expression of the field
  # works in the search of the options, too.
  defp options_query(assigns) do
    %{queryable: queryable, field_options: field_options} = assigns

    queryable
    |> from_named(binding_name(field_options, queryable))
    |> maybe_options_query(field_options, assigns)
  end

  defp from_named(queryable, nil), do: from(queryable)
  defp from_named(queryable, binding), do: from(queryable, as: ^binding)

  defp binding_name(%{custom_alias: custom_alias}, _queryable), do: custom_alias
  defp binding_name(_field_options, {_source, schema}) when is_atom(schema), do: EctoAdapter.name_by_schema(schema)
  defp binding_name(_field_options, schema) when is_atom(schema), do: EctoAdapter.name_by_schema(schema)
  defp binding_name(_field_options, _queryable), do: nil

  # How the field reads its options, see `Backpex.Fields.OptionsQuery.list/3`. The value of an option is the key of the
  # related item that the foreign key references.
  defp options_opts(%{field_options: field_options} = assigns) do
    search_by =
      case field_options do
        %{display_field_form: display_field_form} -> display_field_form
        %{select: select} -> select
        _field_options -> assigns.display_field_form
      end

    [
      repo: assigns.live_resource.adapter_config(:repo),
      queryable: assigns.queryable,
      label: assigns.display_field_form,
      value: assigns.related_key,
      search_by: search_by
    ]
  end

  # With `query_limit`, the form and the index form keep a page of options, the search and the offset of the next page
  # in the assigns of the component. Without it, they load every option when they render.
  defp assign_server_options(%{assigns: %{field_options: %{query_limit: limit}}} = socket) when is_integer(limit) do
    case socket.assigns do
      %{type: :form} = assigns ->
        assign_form_options(socket, assigns.form[assigns.owner_key].value)

      %{type: :index} = assigns ->
        if Backpex.Field.index_editable_enabled?(assigns.field_options, assigns),
          do: assign_index_form_options(socket),
          else: socket

      _assigns ->
        socket
    end
  end

  defp assign_server_options(socket), do: socket

  # The options query may depend on other assigns, e.g. a value of the form. The options are loaded again whenever the
  # resulting query changes.
  defp assign_form_options(socket, value) do
    query = options_query(socket.assigns)

    socket =
      if Map.get(socket.assigns, :options_base_query) == query do
        socket
      else
        socket
        |> assign(options_base_query: query, offset: 0)
        |> assign_new(:search_input, fn -> "" end)
        |> assign_options()
        |> assign_default_option()
      end

    assign_selected_option(socket, value)
  end

  # Rows share their options while no search or "Show more" changed them. The row keeps its own options otherwise, also
  # when the index view renders again.
  defp assign_index_form_options(socket) do
    %{assigns: assigns} = socket
    primary_value = LiveResource.primary_value(assigns.item, assigns.live_resource)
    socket = assign(socket, options_base_query: options_query(assigns))

    page =
      case assigns do
        %{index_form_pages: %{^primary_value => page}} -> page
        _assigns -> load_index_form_page(socket.assigns)
      end

    socket =
      socket
      |> assign_new(:search_input, fn -> "" end)
      |> assign_new(:offset, fn -> 0 end)
      |> assign(:selected_option, page.selected_option)
      |> assign(:default_option, List.first(page.options))

    if socket.assigns.search_input == "" and socket.assigns.offset == 0,
      do: assign(socket, options: page.options, show_more: page.show_more),
      else: socket
  end

  defp load_index_form_page(assigns) do
    %{options_base_query: query, field_options: field_options, item: item, owner_key: owner_key} = assigns
    opts = options_opts(assigns)

    {options, show_more} = OptionsQuery.page(query, [limit: field_options[:query_limit]], opts)

    selected_option =
      find_option(options, Map.get(item, owner_key)) || fetch_option(query, Map.get(item, owner_key), opts)

    %{options: options, show_more: show_more, selected_option: selected_option}
  end

  defp assign_options(socket, other_options \\ []) do
    OptionsQuery.assign_page(socket, options_opts(socket.assigns), other_options)
  end

  # The first option of the options query, which a select without a prompt selects while the item has no value.
  defp assign_default_option(%{assigns: %{search_input: ""}} = socket) do
    assign(socket, :default_option, List.first(socket.assigns.options))
  end

  defp assign_default_option(socket) do
    %{assigns: %{options_base_query: query} = assigns} = socket

    assign(socket, :default_option, query |> OptionsQuery.list([limit: 1], options_opts(assigns)) |> List.first())
  end

  # The option of the current value, which may be on no loaded page. It is loaded again only when the value or the
  # options query changes.
  defp assign_selected_option(socket, value) do
    %{assigns: %{options_base_query: query} = assigns} = socket

    case assigns do
      %{selected_option_of: {^query, ^value}} ->
        socket

      _assigns ->
        option = find_option(assigns.options, value) || fetch_option(query, value, options_opts(assigns))

        assign(socket, selected_option: option, selected_option_of: {query, value})
    end
  end

  defp find_option(_options, value) when value in [nil, ""], do: nil
  defp find_option(options, value), do: Enum.find(options, fn {_label, key} -> to_string(key) == to_string(value) end)

  defp fetch_option(_query, value, _opts) when value in [nil, ""], do: nil

  defp fetch_option(query, value, opts) do
    case cast_value(opts[:queryable], opts[:value], value) do
      {:ok, id} -> query |> OptionsQuery.list([ids: [id], limit: 1], opts) |> List.first()
      _error -> nil
    end
  end

  # The assigns of the select in the form: the options the component loaded with `query_limit`, else every option.
  defp assign_form_select(%{field_options: %{query_limit: limit}} = assigns) when is_integer(limit) do
    assign_search_select(assigns)
  end

  defp assign_form_select(assigns) do
    options = assigns |> options_query() |> OptionsQuery.list([], options_opts(assigns))

    assign_local_select(assigns, options)
  end

  defp assign_index_form_select(%{field_options: %{query_limit: limit}} = assigns) when is_integer(limit) do
    assign_search_select(assigns)
  end

  defp assign_index_form_select(assigns) do
    primary_value = LiveResource.primary_value(assigns.item, assigns.live_resource)

    options =
      case assigns do
        %{index_form_options: %{^primary_value => options}} -> options
        _assigns -> assigns |> options_query() |> OptionsQuery.list([], options_opts(assigns))
      end

    assign_local_select(assigns, options)
  end

  defp assign_search_select(assigns) do
    assigns
    |> assign(:selected_options, Enum.reject([assigns.selected_option, assigns.default_option], &is_nil/1))
    |> assign(:on_search, "search")
    |> assign(:search_target, assigns.myself)
    |> assign(:searchable, true)
  end

  defp assign_local_select(assigns, options) do
    assigns
    |> assign(:options, options)
    |> assign(:default_option, List.first(options))
    |> assign(:selected_options, [])
    |> assign(:show_more, false)
    |> assign(:on_search, nil)
    |> assign(:search_target, nil)
    |> assign(:searchable, assigns.field_options[:searchable_options] == true)
  end

  defp assign_link(assigns) do
    %{socket: socket, field_options: field_options, value: value, params: params} = assigns

    live_resource = Map.get(field_options, :live_resource)

    link =
      if live_resource && Authorization.can?(live_resource, assigns, :show, value) do
        Router.get_path(socket, live_resource, params, :show, value)
      end

    assign(assigns, :link, link)
  end

  defp maybe_options_query(query, %{options_query: options_query} = _field_options, assigns),
    do: options_query.(query, assigns)

  defp maybe_options_query(query, _field_options, _assigns), do: query

  defp assign_prompt(assigns, field_options) do
    prompt =
      case Map.get(field_options, :prompt) do
        nil -> nil
        prompt when is_function(prompt) -> prompt.(assigns)
        prompt -> prompt
      end

    assign(assigns, :prompt, prompt)
  end
end
