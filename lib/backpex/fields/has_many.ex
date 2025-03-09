defmodule Backpex.Fields.HasMany do
  @config_schema [
    display_field: [
      doc: "The field of the relation to be used for searching, ordering and displaying values.",
      type: :atom,
      required: true
    ],
    display_field_form: [
      doc: "The field to be used to display form values.",
      type: :atom
    ],
    live_resource: [
      doc: "The live resource of the association.",
      type: :atom
    ],
    link_assocs: [
      doc: "Whether to automatically generate links to the association items.",
      type: :boolean,
      default: true
    ],
    options_query: [
      doc: """
      Manipulates the list of available options in the multi select.

      Defaults to `fn (query, _field) -> query end` which returns all entries.
      """,
      type: {:fun, 2}
    ],
    prompt: [
      doc: """
      The text to be displayed when no options are selected or function that receives the assigns.

      The default value is `"Select options..."`.
      """,
      type: {:or, [:string, {:fun, 1}]}
    ],
    not_found_text: [
      doc: """
      The text to be displayed when no options are found.

      The default value is `"No options found"`.
      """,
      type: :string
    ],
    query_limit: [
      doc: "Limit passed to the query to fetch new items. Set to `nil` to have no limit.",
      type: {:or, [:non_neg_integer, nil]},
      default: 10
    ]
  ]

  @moduledoc """
  A field for handling a `has_many` or `many_to_many` relation.

  This field can not be orderable or searchable.

  ## Field-specific options

  See `Backpex.Field` for general field options.

  #{NimbleOptions.docs(@config_schema)}

  ## Example

      @impl Backpex.LiveResource
      def fields do
      [
        posts: %{
          module: Backpex.Fields.HasMany,
          label: "Posts",
          display_field: :title,
          options_query: &where(&1, [user], user.role == :admin),
          live_resource: DemoWeb.PostLive
        }
      ]
      end
  """
  use Backpex.Field, config_schema: @config_schema
  import Ecto.Query
  alias Backpex.Adapters.Ecto, as: EctoAdapter
  alias Backpex.HTML.Form
  alias Backpex.Router

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    socket
    |> assign(assigns)
    |> apply_action(assigns.type)
    |> ok()
  end

  defp apply_action(socket, :index) do
    assign_new(socket, :link_assocs, fn -> socket.assigns.field_options[:link_assocs] end)
  end

  defp apply_action(socket, :form) do
    %{assigns: %{field_options: field_options} = assigns} = socket

    socket
    |> assign_new(:prompt, fn -> prompt(assigns, field_options) end)
    |> assign_new(:not_found_text, fn -> field_options[:not_found_text] || Backpex.translate("No options found") end)
    |> assign_new(:search_input, fn -> "" end)
    |> assign_new(:offset, fn -> 0 end)
    |> assign_new(:options_count, fn -> count_options(assigns) end)
    |> assign_initial_options()
    |> assign_selected()
    |> assign_form_errors()
  end

  defp apply_action(socket, _type), do: socket

  @impl Backpex.Field
  def render_value(assigns) do
    ~H"""
    <div class={[@live_action in [:index, :resource_action] && "truncate"]}>
      {if @value == [], do: raw("&mdash;")}

      <div class={["flex", @live_action == :show && "flex-wrap"]}>
        <.intersperse :let={item} enum={@value |> Enum.sort_by(&Map.get(&1, display_field(@field)), :asc)}>
          <:separator>
            ,&nbsp;
          </:separator>
          <.item
            socket={@socket}
            field={@field}
            field_options={@field_options}
            params={@params}
            live_resource={@live_resource}
            live_action={@live_action}
            item={item}
            link_assocs={@link_assocs}
          />
        </.intersperse>
      </div>
    </div>
    """
  end

  @impl Backpex.Field
  def render_form(assigns) do
    ~H"""
    <div id={@name}>
      <Layout.field_container>
        <:label align={Backpex.Field.align_label(@field_options, assigns)}>
          <Layout.input_label text={@field_options[:label]} />
        </:label>
        <div class="dropdown w-full">
          <label
            tabindex="0"
            class={[
              "input block h-fit w-full p-2",
              @errors == [] && "bg-transparent",
              @errors != [] && "input-error bg-error/10 input-ghost"
            ]}
          >
            <div class="flex h-full w-full flex-wrap items-center gap-1 px-2">
              <p :if={@selected == []} class="p-0.5 text-sm">
                {@prompt}
              </p>

              <div :for={{label, value} <- @selected} class="badge badge-primary p-[11px]">
                <p class="mr-1">
                  {label}
                </p>

                <label
                  role="button"
                  for={"has-many-#{@name}-checkbox-value-#{value}"}
                  aria-label={Backpex.translate({"Unselect %{label}", %{label: label}})}
                >
                  <Backpex.HTML.CoreComponents.icon name="hero-x-mark" class="text-base-100 ml-1 h-4 w-4" />
                </label>
              </div>
            </div>
          </label>
          <Form.error :for={msg <- @errors}>{msg}</Form.error>
          <div tabindex="0" class="dropdown-content z-[1] menu bg-base-100 rounded-box w-full overflow-y-auto shadow">
            <div class="max-h-72 p-2">
              <input
                type="search"
                name={"#{@name}_search"}
                class="input input-sm mb-2 w-full"
                phx-change="search"
                phx-target={@myself}
                placeholder={Backpex.translate("Search")}
                value={@search_input}
              />
              <p :if={@options == []} class="w-full">
                {@not_found_text}
              </p>

              <label :if={Enum.any?(@options)}>
                <input
                  type="checkbox"
                  class="hidden"
                  name={if @all_selected, do: "change[#{@name}_deselect_all]", else: "change[#{@name}_select_all]"}
                  value=""
                />
                <span role="button" class="text-primary my-2 cursor-pointer text-sm underline">
                  <%= if @all_selected do %>
                    {Backpex.translate("Deselect all")}
                  <% else %>
                    {Backpex.translate("Select all")}
                  <% end %>
                </span>
              </label>

              <input type="hidden" id={"has-many-#{@name}-hidden-input"} name={"#{@form[@name].name}[]"} value="" />

              <input
                :for={value <- @selected_ids}
                :if={value not in @options_ids}
                id={"has-many-#{@name}-checkbox-value-#{value}"}
                type="checkbox"
                value={value}
                name={"#{@form[@name].name}[]"}
                class="hidden"
                checked
              />

              <div class="my-2 w-full">
                <label :for={{label, value} <- @options} class={["mt-2 flex cursor-pointer items-center gap-x-2"]}>
                  <input
                    id={"has-many-#{@name}-checkbox-value-#{value}"}
                    type="checkbox"
                    name={"#{@form[@name].name}[]"}
                    value={value}
                    checked={value in @selected_ids}
                    class="checkbox checkbox-sm checkbox-primary"
                  />
                  <span class="label-text">
                    {label}
                  </span>
                </label>
              </div>

              <button
                :if={@show_more}
                type="button"
                class="text-primary mb-2 cursor-pointer text-sm underline"
                phx-click="show-more"
                phx-target={@myself}
              >
                {Backpex.translate("Show more")}
              </button>
            </div>
          </div>
        </div>
      </Layout.field_container>
    </div>
    """
  end

  @impl Phoenix.LiveComponent
  def handle_event("search", params, socket) do
    search_input = Map.get(params, to_string(socket.assigns.name) <> "_search", "")

    socket
    |> assign(:offset, 0)
    |> assign(:search_input, search_input)
    |> assign_options()
    |> noreply()
  end

  @impl Phoenix.LiveComponent
  def handle_event("show-more", _params, socket) do
    %{assigns: %{field_options: field_options, offset: offset, options: options}} = socket

    socket
    |> assign(:offset, field_options[:query_limit] + offset)
    |> assign_options(options)
    |> noreply()
  end

  @impl Backpex.Field
  def display_field({_name, field_options}), do: Map.get(field_options, :display_field)

  @impl Backpex.Field
  def association?(_field), do: true

  @impl Backpex.Field
  def schema({name, _field_options}, schema) do
    schema.__schema__(:association, name)
    |> Map.get(:queryable)
  end

  @impl Backpex.Field
  def before_changeset(changeset, attrs, _metadata, repo, field, assigns) do
    {field_name, field_options} = field
    validate_live_resource(field_name, field_options)

    # TODO: do not rely on specific adapter
    schema = field_options.live_resource.config(:adapter_config)[:schema]
    field_name_string = to_string(field_name)

    new_assocs = get_new_assocs(attrs, field_name_string, schema, repo, field_options, assigns)

    if is_nil(new_assocs) do
      changeset
    else
      Ecto.Changeset.put_assoc(changeset, field_name, new_assocs)
    end
  end

  defp validate_live_resource(field_name, field_options) do
    if !Map.has_key?(field_options, :live_resource) do
      raise "The field #{field_name} does not have the required key :live_resource defined."
    end
  end

  defp get_new_assocs(attrs, field_name_string, schema, repo, field_options, assigns) do
    cond do
      # It is important add empty maps when selecting or deselecting all items to force the list to be always present
      # in the changes. Otherwise it would not work if the item already contains all items ("select all") or
      # none items ("deselect all").
      Map.has_key?(attrs, field_name_string <> "_select_all") ->
        [%{} | repo.all(schema)]

      Map.has_key?(attrs, field_name_string <> "_deselect_all") ->
        [%{}]

      assoc_ids = Map.get(attrs, field_name_string) ->
        get_assocs_by_ids(assoc_ids, schema, repo, field_options, assigns)

      true ->
        nil
    end
  end

  defp get_assocs_by_ids(assoc_ids, schema, repo, field_options, assigns) do
    case assoc_ids do
      ids when is_list(ids) and ids != [] ->
        filtered_ids = Enum.reject(ids, &(&1 == ""))

        schema
        |> where([x], x.id in ^filtered_ids)
        |> maybe_options_query(field_options, assigns)
        |> repo.all()

      "" ->
        []

      _other ->
        nil
    end
  end

  defp item(assigns) do
    %{field: field, item: item} = assigns

    assigns =
      assigns
      |> assign(:display_text, Map.get(item, display_field(field)))
      |> assign_link()

    ~H"""
    <%= if is_nil(@link) do %>
      <span>
        {HTML.pretty_value(@display_text)}
      </span>
    <% else %>
      <.link navigate={@link} class="hover:underline">
        {@display_text}
      </.link>
    <% end %>
    """
  end

  defp assign_link(assigns) do
    %{
      socket: socket,
      field_options: field_options,
      item: item,
      params: params,
      link_assocs: link_assocs
    } = assigns

    link =
      if link_assocs and field_options.live_resource.can?(assigns, :show, item) do
        Router.get_path(socket, Map.get(field_options, :live_resource), params, :show, item)
      else
        nil
      end

    assign(assigns, :link, link)
  end

  defp assign_initial_options(%{assigns: %{options: _options}} = socket), do: socket

  defp assign_initial_options(socket), do: assign_options(socket)

  defp assign_options(socket, other_options \\ []) do
    %{assigns: %{field_options: field_options, search_input: search_input, offset: offset} = assigns} = socket
    limit = field_options[:query_limit]

    options = other_options ++ options(assigns, offset: offset, limit: limit, search: search_input)

    show_more = count_options(assigns, search: search_input) > length(options)

    socket
    |> assign(:options, options)
    |> assign(:options_ids, Enum.map(options, fn {_label, value} -> value end))
    |> assign(:show_more, show_more)
  end

  defp options(assigns, opts) do
    %{repo: repo, schema: schema, field: field, field_options: field_options, name: name} = assigns

    %{queryable: queryable} = schema.__schema__(:association, name)

    display_field = display_field(field)

    schema_name = EctoAdapter.name_by_schema(queryable)

    from(queryable, as: ^schema_name)
    |> maybe_options_query(field_options, assigns)
    |> maybe_search_query(schema_name, field_options, display_field, Keyword.get(opts, :search))
    |> maybe_offset_query(Keyword.get(opts, :offset))
    |> maybe_limit_query(Keyword.get(opts, :limit))
    |> repo.all()
    |> Enum.map(fn item ->
      {Map.get(item, display_field_form(field)), item.id}
    end)
  end

  defp maybe_limit_query(query, nil), do: query
  defp maybe_limit_query(query, limit), do: query |> limit(^limit)

  defp maybe_offset_query(query, nil), do: query
  defp maybe_offset_query(query, offset), do: query |> offset(^offset)

  defp maybe_options_query(query, %{options_query: options_query}, assigns), do: options_query.(query, assigns)
  defp maybe_options_query(query, _field_options, _assigns), do: query

  defp maybe_search_query(query, _schema_name, _field_options, _display_field, nil), do: query

  defp maybe_search_query(query, schema_name, field_options, display_field, search_input) do
    if String.trim(search_input) == "" do
      query
    else
      search_input = "%#{search_input}%"
      select = Map.get(field_options, :select, nil)

      if select do
        where(query, ^dynamic(ilike(^select, ^search_input)))
      else
        where(query, [{^schema_name, schema_name}], ilike(field(schema_name, ^display_field), ^search_input))
      end
    end
  end

  defp count_options(assigns, opts \\ []) do
    %{schema: schema, repo: repo, field: field, field_options: field_options, name: name} = assigns

    display_field = display_field(field)

    %{queryable: queryable} = schema.__schema__(:association, name)
    schema_name = EctoAdapter.name_by_schema(queryable)

    from(queryable, as: ^schema_name)
    |> maybe_options_query(field_options, assigns)
    |> maybe_search_query(schema_name, field_options, display_field, Keyword.get(opts, :search))
    |> subquery()
    |> repo.aggregate(:count)
  end

  def assign_selected(socket) do
    {field_name, field_options} = socket.assigns.field
    validate_live_resource(field_name, field_options)

    primary_key = field_options.live_resource.config(:primary_key)

    selected_ids = extract_selected_ids(socket.assigns.form[socket.assigns.name].value, primary_key)
    selected_items = fetch_selected_items(socket, selected_ids)

    socket
    |> assign(:selected, selected_items)
    |> assign(:selected_ids, selected_ids)
    |> assign(:all_selected, length(selected_items) == socket.assigns.options_count)
  end

  defp fetch_selected_items(socket, selected_ids) do
    %{queryable: queryable} = socket.assigns.schema.__schema__(:association, socket.assigns.name)
    {from_options, to_fetch} = separate_selected_items(selected_ids, socket.assigns.options)
    from_db = fetch_from_db(to_fetch, queryable, socket)

    from_options ++ from_db
  end

  defp separate_selected_items(selected_ids, options) do
    options_map = Map.new(options, fn {label, id} -> {id, {label, id}} end)

    Enum.reduce(selected_ids, {[], []}, fn id, {from_options, to_fetch} ->
      case Map.get(options_map, id) do
        nil -> {from_options, [id | to_fetch]}
        item -> {[item | from_options], to_fetch}
      end
    end)
  end

  defp fetch_from_db([], _queryable, _socket), do: []

  defp fetch_from_db(ids_to_fetch, queryable, socket) do
    queryable
    |> where([x], x.id in ^ids_to_fetch)
    |> maybe_options_query(socket.assigns.field_options, socket.assigns)
    |> socket.assigns.repo.all()
    |> Enum.map(fn item ->
      {Map.get(item, display_field_form(socket.assigns.field)), item.id}
    end)
  end

  defp extract_selected_ids(value, primary_key) when is_list(value) and is_atom(primary_key) do
    Enum.reduce(value, [], fn
      %Ecto.Changeset{data: data, action: :update}, acc ->
        [Map.fetch!(data, primary_key) | acc]

      %Ecto.Changeset{}, acc ->
        acc

      struct, acc when is_struct(struct) ->
        [Map.fetch!(struct, primary_key) | acc]

      entry, acc when is_binary(entry) and entry != "" ->
        [entry | acc]

      _entry, acc ->
        acc
    end)
  end

  defp extract_selected_ids(_value, _primary_key), do: []

  defp assign_form_errors(socket) do
    %{assigns: %{form: form, name: name, field_options: field_options}} = socket

    errors = if Phoenix.Component.used_input?(form[name]), do: form[name].errors, else: []
    translate_error_fun = Map.get(field_options, :translate_error, &Function.identity/1)

    assign(socket, :errors, Form.translate_form_errors(errors, translate_error_fun))
  end

  defp display_field_form({_name, field_options} = field),
    do: Map.get(field_options, :display_field_form, display_field(field))

  defp prompt(assigns, field_options) do
    case Map.get(field_options, :prompt) do
      nil -> Backpex.translate("Select options...")
      prompt when is_function(prompt) -> prompt.(assigns)
      prompt -> prompt
    end
  end
end
