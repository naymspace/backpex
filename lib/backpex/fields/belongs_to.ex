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

      Defaults to `fn (query, _field) -> query end` which returns all entries.
      """,
      type: {:fun, 2}
    ],
    prompt: [
      doc: "The text to be displayed when no option is selected or function that receives the assigns.",
      type: {:or, [:string, {:fun, 1}]}
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
          live_resource: DemoWeb.UserLive
        }
      ]
      end
  """
  use Backpex.Field, config_schema: @config_schema
  alias Backpex.Authorization
  alias Backpex.Resource
  alias Backpex.Router

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    %{name: name, field: field, live_resource: live_resource} = assigns
    %{owner_key: owner_key} = Resource.association(name, live_resource)

    display_field = display_field(field)
    display_field_form = display_field_form(field, display_field)

    socket
    |> assign(assigns)
    |> assign(owner_key: owner_key)
    |> assign(display_field: display_field)
    |> assign(display_field_form: display_field_form)
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
      |> assign(:options, options(assigns))
      |> assign(:owner_key, owner_key)
      |> assign_prompt(field_options)

    ~H"""
    <div>
      <Layout.field_container>
        <:label :if={not @hide_label} align={Backpex.Field.align_label(@field_options, assigns)}>
          <Layout.input_label for={@form[@owner_key]} text={@field_options[:label]} />
        </:label>
        <BackpexForm.input
          type="select"
          field={@form[@owner_key]}
          options={@options}
          prompt={@prompt}
          readonly={@readonly}
          disabled={@readonly}
          translate_error_fun={Backpex.Field.translate_error_fun(@field_options, assigns)}
          help_text={Backpex.Field.help_text(@field_options, assigns)}
          phx-debounce={Backpex.Field.debounce(@field_options, assigns)}
          phx-throttle={Backpex.Field.throttle(@field_options, assigns)}
          aria-labelledby={Map.get(assigns, :aria_labelledby)}
        />
      </Layout.field_container>
    </div>
    """
  end

  @impl Backpex.Field
  def index_assigns({name, field_options} = field, items, assigns) do
    if Backpex.Field.index_editable_enabled?(field_options, assigns) do
      %{live_resource: live_resource} = assigns
      display_field_form = display_field_form(field, display_field(field))

      field_assigns =
        Map.merge(assigns, %{
          name: name,
          field: field,
          field_options: field_options,
          display_field_form: display_field_form
        })

      assigns_by_item =
        Map.new(items, fn item ->
          {LiveResource.primary_value(item, live_resource),
           Map.merge(field_assigns, %{item: item, value: Map.get(item, name)})}
        end)

      {:ok, options_by_item} = Resource.list_options_by_key(field, [], assigns_by_item, live_resource)

      %{
        index_form_options:
          Map.new(options_by_item, fn {key, options} -> {key, to_options(options, display_field_form)} end)
      }
    else
      %{}
    end
  end

  @impl Backpex.Field
  def render_index_form(assigns) do
    primary_value = LiveResource.primary_value(assigns.item, assigns.live_resource)

    options =
      case assigns do
        %{index_form_options: %{^primary_value => options}} -> options
        _assigns -> options(assigns)
      end

    assigns =
      assigns
      |> assign(:options, options)
      |> Backpex.Field.assign_index_form()
      |> assign_prompt(assigns.field_options)

    ~H"""
    <div>
      <BackpexForm.index_form form={@form} name={@name} item={@item} live_resource={@live_resource} class="relative">
        <BackpexForm.input
          id={"index-form-input-#{@name}-#{LiveResource.primary_value(@item, @live_resource)}"}
          type="select"
          field={@form[:value]}
          options={@options}
          prompt={@prompt}
          value={if @valid, do: @value && Map.get(@value, :id), else: @form[:value].value}
          input_class={[
            "select select-sm",
            @valid && "not-hover:select-ghost",
            !@valid &&
              "select-error text-error-content bg-error/10 [&.select::picker(select)]:bg-base-100 [&.select::picker(select)]:text-base-content"
          ]}
          disabled={@readonly}
          hide_errors
          aria-label={@field_options[:label]}
        />
      </BackpexForm.index_form>
    </div>
    """
  end

  @impl Backpex.Field
  def index_editable_change({name, _field_options} = field, value, assigns) do
    %{owner_key: owner_key} = Resource.association(name, assigns.live_resource)

    if option?(field, value, assigns), do: %{owner_key => value}, else: :error
  end

  # The value comes from the client, so only an option of the select, or no option, is saved.
  defp option?(_field, value, _assigns) when value in [nil, ""], do: true

  defp option?(field, value, assigns) do
    assigns = Map.put(assigns, :display_field_form, display_field_form(field, display_field(field)))

    match?({:ok, [_option]}, Resource.list_options(field, [ids: [value], limit: 1], assigns, assigns.live_resource))
  end

  @impl Backpex.Field
  def display_field({_name, field_options}) do
    Map.get(field_options, :display_field)
  end

  @impl Backpex.Field
  def association?(_field), do: true

  defp display_field_form({_name, field_options} = _field, display_field) do
    Map.get(field_options, :display_field_form, display_field)
  end

  defp options(assigns) do
    {:ok, options} = Resource.list_options(assigns.field, [], assigns, assigns.live_resource)

    to_options(options, assigns.display_field_form)
  end

  defp to_options(options, display_field) do
    Enum.map(options, &{Map.get(&1, display_field), Map.get(&1, :id)})
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
