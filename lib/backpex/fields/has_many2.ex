defmodule Backpex.Fields.HasMany2 do
  @moduledoc """
  """
  use BackpexWeb, :field

  alias Backpex.Resource

  import Ecto.Query

  alias Backpex.Router

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_options()

    {:ok, socket}
  end

  defp assign_options(socket) do
    assign(socket, :options, options(socket.assigns))
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

  @impl Backpex.Field
  def render_form(assigns) do
    checked =
      case assigns.form[assigns.name].value do
        [_head | _tail] ->
          Enum.reduce(assigns.form[assigns.name].value, [], fn
            %Ecto.Changeset{data: %{id: id}, action: :update}, acc ->
              [id | acc]

            %{id: id} = _entry, acc ->
              [id | acc]

            entry, acc when is_binary(entry) ->
              [entry | acc]

            _entry, acc ->
              acc
          end)

        _other ->
          []
      end

    assigns =
      assigns
      |> assign_new(:checked, fn -> checked end)
      |> assign_new(:search_value, fn -> "" end)
      |> assign(:all_checked, length(checked) == length(assigns.options))
      |> assign(:errors, Backpex.HTML.Form.translate_form_errors(assigns.form[assigns.name], assigns.field_options))

    ~H"""
    <div id="has-many" phx-hook="BackpexHasMany">
      <Layout.field_container>
        <:label align={Backpex.Field.align_label(@field_options, assigns, :center)}>
          <Layout.input_label text={@field_options[:label]} />
        </:label>
        <button
          data-toggle-all-btn
          type="button"
          phx-click={JS.dispatch("toggle-all", detail: %{"checkboxValue" => !@all_checked})}
        >
          <span :if={!@all_checked}>Select all</span>
          <span :if={@all_checked}>Deselect all</span>
        </button>

        <div data-badges-container>
          <button
            :for={{label, value} <- @options}
            :if={value in @checked}
            class="badge badge-primary"
            phx-click={JS.dispatch("toggle", detail: %{"value" => value})}
            type="button"
          >
            <%= label %>
          </button>
        </div>

        <input
          type="text"
          name={"#{@name}_search"}
          class="input input-sm input-bordered"
          phx-change="search"
          phx-target={@myself}
          value={@search_value}
          data-search-input
        />

        <div id="container" class="space-y-2" data-checkbox-container>
          <input type="hidden" name={@form[@name].name} value="" />
          <%= for {label, value} <- @options do %>
            <label class={["flex cursor-pointer items-center gap-x-2", !show?(label, @search_value) && "hidden"]}>
              <input
                id={"#{@form[@name].name}[]-#{value}"}
                type="checkbox"
                name={"#{@form[@name].name}[]"}
                value={value}
                checked={value in @checked}
                class="checkbox checkbox-sm checkbox-primary"
              />
              <span class="label-text">
                <%= label %>
              </span>
            </label>
          <% end %>
        </div>
        <Backpex.HTML.Form.error :for={msg <- @errors}><%= msg %></Backpex.HTML.Form.error>
      </Layout.field_container>
    </div>
    """
  end

  defp show?(label, search_value) do
    search_value = search_value |> String.trim() |> String.downcase()
    label = label |> String.trim() |> String.downcase()

    String.contains?(label, search_value) or search_value == ""
  end

  @impl Phoenix.LiveComponent
  def handle_event("search", params, socket) do
    search = Map.get(params, to_string(socket.assigns.name) <> "_search", "")

    socket = assign(socket, :search_value, search)

    {:noreply, socket}
  end

  defp options(assigns) do
    %{repo: repo, schema: schema, field: field, field_options: field_options, name: name} = assigns

    %{queryable: queryable} = schema.__schema__(:association, name)

    display_field = display_field(field)

    schema_name = Resource.name_by_schema(queryable)

    from(queryable, as: ^schema_name)
    |> select([x], {field(x, ^display_field), x.id})
    |> order_by([x], x.id)
    |> repo.all()
  end

  @impl Backpex.Field
  def display_field({_name, field_options}), do: Map.get(field_options, :display_field)

  @impl Backpex.Field
  def association?(_field), do: true
end
