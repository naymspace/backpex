# credo:disable-for-this-file Credo.Check.Design.DuplicatedCode
defmodule Backpex.Fields.HasMany do
  @moduledoc """
  A field for handling a `has_many` relation.

  This field can not be orderable or searchable.

  ## Options

    * `:display_field` - The field of the relation to be used for searching, ordering and displaying values.
    * `:display_field_form` - Optional field to be used to display form values.
    * `:live_resource` - The live resource of the association. Used to generate links navigating to the associations.
    * `:options_query` - Manipulates the list of available options in the multi select.
      Defaults to `fn (query, _field) -> query end` which returns all entries.
    * `:prompt` - The text to be displayed when no options are selected.
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
    socket =
      socket
      |> assign(assigns)
      |> apply_action(assigns.type)

    {:ok, socket}
  end

  defp apply_action(socket, :form) do
    %{assigns: %{field_options: field_options} = assigns} = socket

    socket
    |> assign_new(:prompt, fn -> prompt(field_options) end)
    |> assign_new(:not_found_text, fn -> not_found_text(field_options) end)
    |> assign_new(:search_input, fn -> "" end)
    |> assign_new(:offset, fn -> 0 end)
    |> assign_new(:options_count, fn -> assigns |> options() |> length() end)
    |> assign_initial_options()
    |> assign_selected()
    |> assign_show_select_all()
  end

  defp apply_action(socket, _type), do: socket

  defp assign_show_select_all(%{assigns: %{show_select_all: _show_select_all}} = socket), do: socket

  defp assign_show_select_all(socket) do
    %{selected: selected, options_count: options_count} = socket.assigns

    show_select_all = length(selected) != options_count

    socket
    |> assign(:show_select_all, show_select_all)
  end

  defp assign_initial_options(%{assigns: %{options: _options}} = socket), do: socket

  defp assign_initial_options(socket), do: assign_options(socket)

  defp assign_options(socket, other_options \\ []) do
    %{assigns: %{field_options: field_options, search_input: search_input, offset: offset} = assigns} = socket

    limit = query_limit(field_options)

    options = other_options ++ options(assigns, offset: offset, limit: limit, search: search_input)

    show_more = count_options(assigns, search: search_input) > length(options)

    socket
    |> assign(:options, options)
    |> assign(:show_more, show_more)
  end

  defp options(assigns, opts \\ []) do
    %{repo: repo, schema: schema, field: field, field_options: field_options, name: name} = assigns

    %{queryable: queryable} = schema.__schema__(:association, name)

    display_field = display_field(field)

    schema_name = Resource.name_by_schema(queryable)

    from(queryable, as: ^schema_name)
    |> maybe_options_query(field_options, assigns)
    |> maybe_search_query(schema_name, field_options, display_field, Keyword.get(opts, :search))
    |> maybe_offset_query(Keyword.get(opts, :offset))
    |> maybe_limit_query(Keyword.get(opts, :limit))
    |> repo.all()
  end

  defp maybe_limit_query(query, nil), do: query

  defp maybe_limit_query(query, limit), do: query |> limit(^limit)

  defp maybe_offset_query(query, nil), do: query

  defp maybe_offset_query(query, offset), do: query |> offset(^offset)

  defp maybe_options_query(query, %{options_query: options_query} = _field_options, assigns),
    do: options_query.(query, assigns)

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

  defp count_options(assigns, opts) do
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

  defp assign_selected(%{assigns: %{selected: _selected}} = socket), do: socket

  defp assign_selected(socket) do
    %{assigns: %{name: name, form: form}} = socket

    values =
      case PhoenixForm.input_value(form, name) do
        value when is_binary(value) -> [value]
        value when is_list(value) -> value
        _value -> []
      end

    assign(socket, :selected, values)
  end

  @impl Backpex.Field
  def render_value(assigns) do
    ~H"""
    <div>
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
      |> assign(:options, Enum.map(assigns.options, &to_form_option(&1, assigns.field)))
      |> assign(:selected, Enum.map(assigns.selected, &to_form_option(&1, assigns.field)))

    ~H"""
    <div id={@name}>
      <Layout.field_container>
        <:label align={Backpex.Field.align_label(@field_options, assigns)}>
          <Layout.input_label text={@field_options[:label]} />
        </:label>
        <.multi_select
          form={@form}
          prompt={@prompt}
          not_found_text={@not_found_text}
          options={@options}
          selected={@selected}
          search_input={@search_input}
          name={@name}
          field_options={@field_options}
          show_select_all={@show_select_all}
          show_more={@show_more}
          event_target={@myself}
          search_event="search"
        />
      </Layout.field_container>
    </div>
    """
  end

  @impl Phoenix.LiveComponent
  def handle_event("toggle-option", %{"id" => id}, socket) do
    %{
      assigns: %{
        name: name,
        selected: selected,
        options: options,
        options_count: options_count
      }
    } = socket

    selected_item = Enum.find(selected, fn option -> option.id == id end)

    new_selected =
      if selected_item do
        Enum.reject(selected, fn option -> option.id == id end)
      else
        selected
        |> Enum.reverse()
        |> Kernel.then(&[Enum.find(options, fn option -> option.id == id end) | &1])
        |> Enum.reverse()
      end

    show_select_all = options_count > length(new_selected)

    put_assoc(name, new_selected)

    socket =
      socket
      |> assign(:selected, new_selected)
      |> assign(:show_select_all, show_select_all)

    {:noreply, socket}
  end

  @impl Phoenix.LiveComponent
  def handle_event("search", params, socket) do
    search_input = get_in(params, ["change", "#{socket.assigns.name}_search"])

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

  @impl Phoenix.LiveComponent
  def handle_event("toggle-select-all", _params, socket) do
    %{
      assigns:
        %{name: name, field_options: field_options, show_select_all: show_select_all, options_count: options_count} =
          assigns
    } = socket

    socket =
      if show_select_all do
        options = options(assigns)

        put_assoc(name, options)

        socket
        |> assign(:options, options)
        |> assign(:selected, options)
        |> assign(:show_more, false)
      else
        options = options(assigns, limit: query_limit(field_options))

        show_more = options_count > length(options)

        put_assoc(name, [])

        socket
        |> assign(:options, options)
        |> assign(:selected, [])
        |> assign(:show_more, show_more)
      end
      |> assign(:show_select_all, !show_select_all)
      |> assign(:search_input, "")

    {:noreply, socket}
  end

  defp item(assigns) do
    %{field: field, item: item} = assigns

    assigns =
      assigns
      |> assign(:display_text, Map.get(item, display_field(field)))
      |> assign_link()

    ~H"""
    <%= if is_nil(@link) do %>
      <span class={@live_action in [:index, :resource_action] && "truncate"}>
        <%= HTML.pretty_value(@display_text) %>
      </span>
    <% else %>
      <.link navigate={@link} class={["hover:underline", @live_action in [:index, :resource_action] && "truncate"]}>
        <%= @display_text %>
      </.link>
    <% end %>
    """
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

  defp put_assoc(key, value) do
    send(self(), {:put_assoc, {key, value}})
  end

  defp query_limit(field_options), do: Map.get(field_options, :query_limit, 10)

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

  defp to_form_option(item, field) do
    {
      Map.get(item, display_field_form(field)),
      Map.get(item, :id)
    }
  end

  defp display_field_form({_name, field_options} = field),
    do: Map.get(field_options, :display_field_form, display_field(field))

  defp prompt(%{prompt: prompt} = _field_options), do: prompt
  defp prompt(_field_options), do: Backpex.translate("Select options...")

  defp not_found_text(%{not_found_text: not_found_text} = _field), do: not_found_text
  defp not_found_text(_field_options), do: Backpex.translate("No options found")
end
