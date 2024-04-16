defmodule Backpex.Fields.BelongsTo do
  @moduledoc """
  A field for handling a `belongs_to` relation.

  ## Options

    * `:display_field` - The field of the relation to be used for searching, ordering and displaying values.
    * `:display_field_form` - Optional field to be used to display form values.
    * `:live_resource` - The live resource of the association. Used to generate links navigating to the association.
    * `:options_query` - Manipulates the list of available options in the select.
      Defaults to `fn (query, _field) -> query end` which returns all entries.
    * `:prompt` - The text to be displayed when no option is selected or function that receives the assigns.

  ## Example

      @impl Backpex.LiveResource
      def fields do
      [
        user: %{
          module: Backpex.Fields.BelongsTo,
          label: "Username",
          display_field: :username,
          options_query: &where(&1, [user], user.role == :admin),
          live_resource: DemoWeb.UserLive
        }
      ]
      end
  """
  use BackpexWeb, :field

  import Ecto.Query

  alias Backpex.LiveResource
  alias Backpex.Router

  @impl Backpex.Field
  def render_value(%{value: value} = assigns) when is_nil(value) do
    ~H"""
    <p class={@live_action in [:index, :resource_action] && "truncate"}>
      <%= HTML.pretty_value(nil) %>
    </p>
    """
  end

  @impl Backpex.Field
  def render_value(assigns) do
    %{field: field, value: value} = assigns

    assigns =
      assigns
      |> assign(:display_text, Map.get(value, display_field(field)))
      |> assign_link()

    ~H"""
    <div>
      <%= if @link do %>
        <.link navigate={@link} class={[@live_action in [:index, :resource_action] && "truncate", "hover:underline"]}>
          <%= @display_text %>
        </.link>
      <% else %>
        <p class={@live_action in [:index, :resource_action] && "truncate"}>
          <%= HTML.pretty_value(@display_text) %>
        </p>
      <% end %>
    </div>
    """
  end

  @impl Backpex.Field
  def render_form(assigns) do
    %{schema: schema, repo: repo, field_options: field_options, name: name} = assigns

    %{queryable: queryable, owner_key: owner_key} = schema.__schema__(:association, name)

    display_field = Map.get(field_options, :display_field_form, Map.get(field_options, :display_field))

    options =
      queryable
      |> from()
      |> maybe_options_query(field_options, assigns)
      |> repo.all()
      |> Enum.map(&{Map.get(&1, display_field), Map.get(&1, :id)})

    assigns =
      assigns
      |> assign(:options, options)
      |> assign(:owner_key, owner_key)
      |> assign_prompt(field_options)

    ~H"""
    <div>
      <Layout.field_container>
        <:label align={Backpex.Field.align_label(@field_options, assigns)}>
          <Layout.input_label text={@field_options[:label]} />
        </:label>
        <BackpexForm.field_input
          type="select"
          field={@form[@owner_key]}
          field_options={@field_options}
          options={@options}
          prompt={@prompt}
        />
      </Layout.field_container>
    </div>
    """
  end

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

  defp assign_link(assigns) do
    %{socket: socket, field_options: field_options, value: value, live_resource: live_resource, params: params} =
      assigns

    link =
      if Map.has_key?(field_options, :live_resource) and LiveResource.can?(assigns, :show, value, live_resource) do
        Router.get_path(socket, Map.get(field_options, :live_resource), params, :show, value)
      else
        nil
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
