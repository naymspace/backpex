defmodule Backpex.Fields.CheckboxGroup do
  @config_schema [
    options: [
      doc: "List of options or function that receives the assigns.",
      type: {:or, [{:list, :any}, {:fun, 1}]},
      required: true
    ],
    columns: [
      doc: "Number of columns to display checkboxes (1-4). Defaults to 2.",
      type: :integer,
      default: 2
    ],
    prompt: [
      doc: "The text to be displayed when no option is selected or function that receives the assigns.",
      type: {:or, [:string, {:fun, 1}]}
    ],
    not_found_text: [
      doc: """
      The text to be displayed when no options are found.

      The default value is `"No options found"`.
      """,
      type: :string
    ]
  ]

  @moduledoc """
  A field for handling multiple selections with checkboxes.

  ## Field-specific options

  See `Backpex.Field` for general field options.

  #{NimbleOptions.docs(@config_schema)}

  ## Example

      @impl Backpex.LiveResource
      def fields do
        [
          categories: %{
            module: Backpex.Fields.CheckboxGroup,
            label: "Categories",
            options: fn _assigns ->
              Repo.all(Category)
              |> Enum.map(fn category -> {category.name, category.id} end)
            end,
            columns: 2
          }
        ]
      end
  """
  use Backpex.Field, config_schema: @config_schema
  alias Backpex.HTML.Form
  require Backpex

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    socket
    |> Phoenix.Component.assign(assigns)
    |> Phoenix.Component.assign(
      :not_found_text,
      assigns.field_options[:not_found_text] || Backpex.__("No options found", assigns.live_resource)
    )
    |> Phoenix.Component.assign(:prompt, prompt(assigns, assigns.field_options))
    |> assign_options()
    |> assign_selected()
    |> ok()
  end

  defp prompt(assigns, field_options) do
    case Map.get(field_options, :prompt) do
      nil -> Backpex.__("Select options...", assigns.live_resource)
      prompt when is_function(prompt) -> prompt.(assigns)
      prompt -> prompt
    end
  end

  defp assign_options(socket) do
    %{assigns: %{field_options: field_options} = assigns} = socket

    options =
      case field_options[:options] do
        options_fun when is_function(options_fun, 1) -> options_fun.(assigns)
        options when is_list(options) -> options
      end
      |> Enum.map(fn {label, value} ->
        {to_string(label), to_string(value)}
      end)

    Phoenix.Component.assign(socket, :options, options)
  end

  defp assign_selected(socket) do
    %{assigns: %{type: type, options: options, item: item, name: name} = assigns} = socket

    selected_ids =
      if type == :form do
        values =
          case Phoenix.HTML.Form.input_value(assigns.form, name) do
            value when is_binary(value) -> [value]
            value when is_list(value) -> value
            _value -> []
          end

        Enum.map(values, &to_string/1)
      else
        value = Map.get(item, name)

        if value, do: value, else: []
      end

    selected =
      Enum.reduce(options, [], fn {_label, value} = option, acc ->
        if value in selected_ids do
          [option | acc]
        else
          acc
        end
      end)
      |> Enum.reverse()

    Phoenix.Component.assign(socket, :selected, selected)
  end

  defp get_column_class(columns) when is_integer(columns) and columns >= 1 and columns <= 4 do
    case columns do
      1 -> ""
      2 -> "grid-cols-2"
      3 -> "grid-cols-3"
      4 -> "grid-cols-4"
    end
  end
  defp get_column_class(_), do: ""

  @impl Backpex.Field
  def render_value(assigns) do
    selected_labels = Enum.map(assigns.selected, fn {label, _value} = _option -> label end)

    assigns = Phoenix.Component.assign(assigns, :selected_labels, selected_labels)

    ~H"""
    <div class={[@live_action in [:index, :resource_action] && "truncate"]}>
      <%= if @selected_labels == [], do: Phoenix.HTML.raw("&mdash;") %>

      <div class={["flex", @live_action == :show && "flex-wrap"]}>
        <%= for {item, index} <- Enum.with_index(@selected_labels) do %>
          <p>
            <%= Backpex.HTML.pretty_value(item) %>
          </p>
          <%= if index < length(@selected_labels) - 1 do %>
            <span>,&nbsp;</span>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  @impl Backpex.Field
  def render_form(assigns) do
    columns = Map.get(assigns.field_options, :columns, 2)
    column_class = get_column_class(columns)

    selected_values = Enum.map(assigns.selected, fn {_label, value} -> value end)

    assigns = assigns
    |> Phoenix.Component.assign(:column_class, column_class)
    |> Phoenix.Component.assign(:selected_values, selected_values)

    ~H"""
    <div id={@name} phx-hook="CheckboxGroupHook" data-field={@name}>
      <Backpex.HTML.Layout.field_container>
        <:label align={Backpex.Field.align_label(@field_options, assigns)}>
          <Backpex.HTML.Layout.input_label text={@field_options[:label]} />
        </:label>
        <div>
          <div class={"grid gap-2 " <> if(@column_class != "", do: @column_class, else: "")}>
            <%= for {label, value} <- @options do %>
              <div>
                <label class="flex items-center cursor-pointer">
                  <input
                    type="checkbox"
                    name={"change[#{@name}][]"}
                    value={value}
                    checked={value in @selected_values}
                    class="checkbox checkbox-primary mr-2"
                    phx-click="toggle-option"
                    phx-value-id={value}
                    phx-target={@myself}
                  />
                  <span class="text-sm cursor-pointer">
                    <%= label %>
                  </span>
                </label>
              </div>
            <% end %>
          </div>


          <input type="hidden" name={"change[#{@name}][]"} value="" />
          <script>
            window.addEventListener('phx:update', () => {
              if (!window.CheckboxGroupHook) {
                window.CheckboxGroupHook = {
                  mounted() {
                    this.handleEvent(`checklist:${this.el.dataset.field}:changed`, ({values}) => {
                      // Update the actual checkboxes
                      const checkboxes = this.el.querySelectorAll('input[type="checkbox"]');
                      checkboxes.forEach(checkbox => {
                        checkbox.checked = values.includes(checkbox.value);
                      });
                    });
                  }
                };
              }
            });
          </script>
        </div>
      </Backpex.HTML.Layout.field_container>
    </div>
    """
  end

  @impl Backpex.Field
  def render_index_form(assigns), do: render_form(assigns)

  @impl Backpex.Field
  def render_form_readonly(assigns), do: render_value(assigns)

  @impl Backpex.Field
  def display_field({name, _field_options}), do: name

  @impl Backpex.Field
  def schema(_field, schema), do: schema

  @impl Backpex.Field
  def association?(_field), do: false

  @impl Backpex.Field
  def assign_uploads(_field, socket), do: socket

  @impl Backpex.Field
  def before_changeset(changeset, _attrs, _metadata, _repo, _field, _assigns), do: changeset

  @impl Backpex.Field
  def search_condition(schema_name, field_name, search_string) do
    import Ecto.Query

    dynamic(
      [{^schema_name, schema_name}],
      ilike(fragment("CAST(? AS TEXT)", field(schema_name, ^field_name)), ^search_string)
    )
  end

  @impl Phoenix.LiveComponent
  def handle_event("toggle-option", %{"id" => id}, socket) do
    %{assigns: %{selected: selected, options: options, name: name}} = socket

    selected_item = Enum.find(selected, fn {_label, value} -> value == id end)

    new_selected =
      if selected_item do
        Enum.reject(selected, fn {_label, value} -> value == id end)
      else
        selected
        |> Enum.reverse()
        |> Kernel.then(&[Enum.find(options, fn {_label, value} -> value == id end) | &1])
        |> Enum.reverse()
      end

    new_selected_values = Enum.map(new_selected, fn {_label, value} -> value end)
    target_value = %{"_target" => ["change", "#{name}"], "change" => %{to_string(name) => new_selected_values}}
    send(self(), {:validate_change, target_value})

    socket
    |> Phoenix.Component.assign(:selected, new_selected)
    |> push_event("checklist:#{name}:changed", %{values: new_selected_values})
    |> noreply()
  end
end
