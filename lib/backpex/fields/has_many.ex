defmodule Backpex.Fields.HasMany do
  @moduledoc """
  A field for handling a `has_many` or `many_to_many` relation.

  This field can not be orderable or searchable.

  ## Options

    * `:display_field` - The field of the relation to be used for searching, ordering and displaying values.
    * `:display_field_form` - Optional field to be used to display form values.
    * `:live_resource` - The live resource of the association. Used to generate links navigating to the associations.
    * `:options_query` - Manipulates the list of available options in the multi select.
      Defaults to `fn (query, _field) -> query end` which returns all entries.
    * `:prompt` - The text to be displayed when no options are selected or function that receives the assigns.
      Defaults to "Select options...".
    * `:not_found_text` - The text to be displayed when no options are found.
      Defaults to "No options found".
    * `:live_resource` - Optional live resource module used to generate links to the corresponding show view for the item.
    * `:query_limit` - Optional limit passed to the query to fetch new items. Set to `nil` to have no limit.
      Defaults to 10.

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
  use BackpexWeb, :field

  import Ecto.Query
  import Backpex.HTML.Form

  alias Backpex.LiveResource
  alias Backpex.Resource
  alias Backpex.Router

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    socket = assign(socket, assigns)

    {:ok, socket}
  end

  @impl Backpex.Field
  def render_value(assigns) do
    ~H"""
    <div class={[@live_action in [:index, :resource_action] && "truncate"]}>
      <%= if @value == [], do: raw("&mdash;") %>

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
          />
        </.intersperse>
      </div>
    </div>
    """
  end

  @impl Backpex.Field
  def render_form(assigns) do
    assigns =
      assigns
      |> assign_new(:prompt, fn -> prompt(assigns, assigns.field_options) end)
      |> assign_new(:not_found_text, fn -> not_found_text(assigns.field_options) end)
      |> assign_new(:search_input, fn -> "" end)
      |> assign_new(:offset, fn -> 0 end)
      |> assign_new(:options_count, fn -> count_options(assigns) end)
      |> assign_initial_options()
      |> assign_selected()
      |> assign_form_errors()

    ~H"""
    <div id={@name}>
      <Layout.field_container>
        <:label align={Backpex.Field.align_label(@field_options, assigns)}>
          <Layout.input_label text={@field_options[:label]} />
        </:label>
        <div class="dropdown w-full">
          <label
            tabindex="0"
            class={["input input-bordered block h-fit w-full p-2", @errors != [] && "bg-error/10 input-error"]}
          >
            <div class="flex h-full w-full flex-wrap items-center gap-1 px-2">
              <p :if={@selected == []} class="p-0.5 text-sm">
                <%= @prompt %>
              </p>

              <div :for={{label, value} <- @selected} class="badge badge-primary p-[11px]">
                <p class="mr-1">
                  <%= label %>
                </p>

                <label
                  role="button"
                  for={"has-many-#{@name}-checkbox-value-#{value}"}
                  aria-label={Backpex.translate({"Unselect %{label}", %{label: label}})}
                >
                  <Backpex.HTML.CoreComponents.icon name="hero-x-mark" class="ml-1 h-4 w-4 text-base-100" />
                </label>
              </div>
            </div>
          </label>
          <.error :for={msg <- @errors}><%= msg %></.error>
          <div tabindex="0" class="dropdown-content z-[1] menu bg-base-100 rounded-box w-full overflow-y-auto shadow">
            <div class="max-h-72 p-2">
              <input
                type="search"
                name={"#{@name}_search"}
                class="input input-sm input-bordered mb-2 w-full"
                phx-change="search"
                phx-target={@myself}
                placeholder={Backpex.translate("Search")}
                value={@search_input}
              />
              <p :if={@options == []} class="w-full">
                <%= @not_found_text %>
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
                    <%= Backpex.translate("Deselect all") %>
                  <% else %>
                    <%= Backpex.translate("Select all") %>
                  <% end %>
                </span>
              </label>

              <input type="hidden" id={"has-many-#{@name}-hidden-input"} name={@form[@name].name} value="" />

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
                    <%= label %>
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
                <%= Backpex.translate("Show more") %>
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

    socket =
      socket
      |> assign(:offset, 0)
      |> assign(:search_input, search_input)
      |> assign_options()

    {:noreply, socket}
  end

  @impl Phoenix.LiveComponent
  def handle_event("show-more", _params, socket) do
    %{assigns: %{field_options: field_options, offset: offset, options: options}} = socket

    socket =
      socket
      |> assign(:offset, query_limit(field_options) + offset)
      |> assign_options(options)

    {:noreply, socket}
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

    assoc_live_resource = Map.get(field_options, :live_resource)

    if is_nil(assoc_live_resource) do
      raise """
      The field #{field_name} does not have the required key :live_resource defined.
      """
    end

    schema = assoc_live_resource.schema()
    field_name_string = to_string(field_name)

    new_assocs =
      cond do
        Map.has_key?(attrs, field_name_string <> "_select_all") ->
          # It is important add an empty map to force the list to be always present in the changes.
          # Otherwise the "select all" would not work if the item already contains all items.
          [%{} | repo.all(schema)]

        Map.has_key?(attrs, field_name_string <> "_deselect_all") ->
          []

        assoc_ids = Map.get(attrs, field_name_string) ->
          case assoc_ids do
            ids when is_list(ids) and ids != [] ->
              schema
              |> where([x], x.id in ^ids)
              |> maybe_options_query(field_options, assigns)
              |> repo.all()

            "" ->
              []

            _ ->
              nil
          end
      end

    if is_nil(new_assocs) do
      changeset
    else
      Ecto.Changeset.put_assoc(changeset, field_name, new_assocs)
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
        <%= HTML.pretty_value(@display_text) %>
      </span>
    <% else %>
      <.link navigate={@link} class="hover:underline">
        <%= @display_text %>
      </.link>
    <% end %>
    """
  end

  defp assign_link(assigns) do
    %{socket: socket, field_options: field_options, item: item, live_resource: live_resource, params: params} = assigns

    link =
      if Map.has_key?(field_options, :live_resource) and LiveResource.can?(assigns, :show, item, live_resource) do
        Router.get_path(socket, Map.get(field_options, :live_resource), params, :show, item)
      else
        nil
      end

    assign(assigns, :link, link)
  end

  defp assign_initial_options(%{options: _options} = assigns), do: assigns

  defp assign_initial_options(assigns), do: assign_options(assigns)

  defp assign_options(assigns, other_options \\ []) do
    %{field_options: field_options, search_input: search_input, offset: offset} = assigns

    limit = query_limit(field_options)

    options = other_options ++ options(assigns, offset: offset, limit: limit, search: search_input)

    show_more = count_options(assigns, search: search_input) > length(options)

    assigns
    |> assign(:options, options)
    |> assign(:options_ids, Enum.map(options, fn {_label, value} -> value end))
    |> assign(:show_more, show_more)
  end

  defp options(assigns, opts) do
    %{repo: repo, schema: schema, field: field, field_options: field_options, name: name} = assigns

    %{queryable: queryable} = schema.__schema__(:association, name)

    display_field = display_field(field)

    schema_name = Resource.name_by_schema(queryable)

    from(queryable, as: ^schema_name)
    |> maybe_options_query(field_options, assigns)
    |> maybe_search_query(schema_name, field_options, display_field, Keyword.get(opts, :search))
    |> maybe_offset_query(Keyword.get(opts, :offset))
    |> maybe_limit_query(Keyword.get(opts, :limit))
    |> select([x], {field(x, ^display_field_form(field)), x.id})
    |> repo.all()
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
    schema_name = Resource.name_by_schema(queryable)

    from(queryable, as: ^schema_name)
    |> maybe_options_query(field_options, assigns)
    |> maybe_search_query(schema_name, field_options, display_field, Keyword.get(opts, :search))
    |> subquery()
    |> repo.aggregate(:count, :id)
  end

  defp assign_selected(assigns) do
    %{form: form, field: field, name: name, schema: schema, repo: repo, options_count: options_count} = assigns

    %{queryable: queryable} = schema.__schema__(:association, name)
    schema_name = Resource.name_by_schema(queryable)

    selected_ids =
      case form[name].value do
        [_head | _tail] ->
          Enum.reduce(form[name].value, [], fn
            # new association
            %Ecto.Changeset{data: %{id: id}, action: :update}, acc ->
              [id | acc]

            # struct on initial load
            %{id: id} = _entry, acc ->
              [id | acc]

            # checkbox value
            entry, acc when is_binary(entry) ->
              [entry | acc]

            _entry, acc ->
              acc
          end)

        _other ->
          []
      end

    # TODO: fetch from options first to not load some items twice
    selected =
      from(queryable, as: ^schema_name)
      |> where([x], x.id in ^selected_ids)
      |> maybe_options_query(assigns.field_options, assigns)
      |> select([x], {field(x, ^display_field_form(field)), x.id})
      |> repo.all()

    assigns
    |> assign(:selected, selected)
    |> assign(:all_selected, length(selected) == options_count)
    |> assign(:selected_ids, Enum.map(selected, fn {_label, value} -> value end))
  end

  defp assign_form_errors(assigns) do
    %{form: form, name: name, field_options: field_options} = assigns

    assign(assigns, :errors, translate_form_errors(form[name], field_options))
  end

  defp query_limit(field_options), do: Map.get(field_options, :query_limit, 10)

  defp display_field_form({_name, field_options} = field),
    do: Map.get(field_options, :display_field_form, display_field(field))

  defp prompt(assigns, field_options) do
    case Map.get(field_options, :prompt) do
      nil -> Backpex.translate("Select options...")
      prompt when is_function(prompt) -> prompt.(assigns)
      prompt -> prompt
    end
  end

  defp not_found_text(%{not_found_text: not_found_text} = _field), do: not_found_text
  defp not_found_text(_field_options), do: Backpex.translate("No options found")
end
