# quokka:skip-module-directive-reordering
defmodule Backpex.Fields.InlineCRUD do
  @config_schema [
    type: [
      doc: "The type of the field.",
      type: {:in, [:embed, :assoc]},
      required: true
    ],
    child_fields: [
      doc: """
      A list of child input fields.

      The following fields are **not** supported:
      - `Backpex.Fields.HasManyThrough`
      - `Backpex.Fields.InlineCRUD`
      - `Backpex.Fields.Upload`

      You can add additional classes to child field inputs by setting the class option in the list of `child_fields`.
      The class can be a string or a function that takes the assigns and must return a string.
      """,
      type: :keyword_list,
      required: true
    ],
    live_resource: [
      doc:
        "The live resource of the association. When provided, a link to each item's show page is rendered in the read-only view.",
      type: :atom
    ]
  ]

  @moduledoc """
  A field to handle inline CRUD operations. It can be used with either an `embeds_many` or `has_many` (association) type column.

  ## Field-specific options

  See `Backpex.Field` for general field options.

  #{NimbleOptions.docs(@config_schema)}

  ### EmbedsMany

  The field in the migration must be of type `:map`. You also need to use ecto's `cast_embed/2` in the changeset.

  ### Example

      def changeset(your_schema, attrs) do
        your_schema
        ...
        |> cast_embed(:your_field,
          with: &your_field_changeset/2,
          sort_param: :your_field_order,
          drop_param: :your_field_delete
        )
        ...
      end

  > #### Important {: .info}
  >
  > We use the Ecto `:sort_param` and `:drop_param` to keep track of order and dropped items. Therefore, you need to use these options as well in your changeset. The name has to be `<field_name>_order` and `<field_name>_delete`.

  ### HasMany (Association)

  A HasMany relation does not require any special configuration. You can simply define a basic `Ecto.Schema.has_many/3` relation to be used with the Backpex.Fields.InlineCRUD field.

  > #### Important {: .info}
  >
  > You need to set `on_replace: :delete` to be able to delete items, and `on_delete: :delete_all` to be able to delete a resource with existing items. It is recommended that you also add `on_delete: :delete_all` to your migration.

  ### Example

      @impl Backpex.LiveResource
      def fields do
        [
          embeds_many: %{
            module: Backpex.Fields.InlineCRUD,
            label: "EmbedsMany",
            type: :embed,
            except: [:index],
            child_fields: [
              field1: %{
                module: Backpex.Fields.Text,
                label: "Label1"
              },
              field2: %{
                module: Backpex.Fields.Text,
                label: "Label2"
              }
            ]
          }
        ]
      end
  """
  use Backpex.Field, config_schema: @config_schema

  alias Backpex.Router

  require Backpex

  @impl Phoenix.LiveComponent
  def update(%{field: {name, field_options}} = assigns, socket) do
    child_fields =
      field_options.child_fields
      |> validated_fields(name)
      |> Backpex.LiveResource.fields_by_action(assigns.live_action)
      |> Backpex.LiveResource.fields_by_can(assigns)

    socket
    |> assign(assigns)
    |> assign(child_fields: child_fields)
    |> apply_action(assigns.type)
    |> ok()
  end

  defp apply_action(socket, :form) do
    assign_form_errors(socket)
  end

  defp apply_action(socket, _type), do: socket

  defp validated_fields(fields, parent_name) do
    fields
    |> Enum.map(fn {name, options} = field ->
      options.module.validate_config!(field, parent_name)
      |> Map.new()
      |> then(&{name, &1})
    end)
  end

  @impl Backpex.Field
  def render_value(assigns) do
    ~H"""
    <div class="ring-base-content/10 rounded-box overflow-x-auto ring-1">
      <table class="table">
        <thead class="bg-base-200/50 text-base-content uppercase">
          <tr>
            <th :for={{_name, %{label: label}} <- @child_fields} class="font-medium">
              {label}
            </th>
            <th :if={@field_options[:live_resource]} class="font-medium">
              <span class="sr-only">{Backpex.__("Actions", @live_resource)}</span>
            </th>
          </tr>
        </thead>
        <tbody class="text-base-content/75">
          <tr :for={{row, index} <- Enum.with_index(@value)} class="border-base-content/10 border-b last:border-b-0">
            <td :for={{name, field_options} <- @child_fields}>
              {Backpex.HTML.Resource.inlined_resource_field(
                assign(assigns,
                  id: "inlined_#{Map.get(@item, @live_resource.config(:primary_key))}_#{@name}_#{name}_#{index}",
                  fields: @child_fields,
                  name: name,
                  item: row
                )
              )}
            </td>
            <%= if link = get_link(assigns, row) do %>
              <td>
                <div class="tooltip" data-tip={Backpex.__("Show", @live_resource)}>
                  <.link navigate={link} aria-label={Backpex.__("Show", @live_resource)}>
                    <Backpex.HTML.CoreComponents.icon
                      name="hero-eye"
                      class="h-5 w-5 cursor-pointer transition duration-75 hover:text-success hover:scale-110"
                    />
                  </.link>
                </div>
              </td>
            <% else %>
              <td :if={@field_options[:live_resource]} />
            <% end %>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  @impl Backpex.Field
  def render_form(assigns) do
    ~H"""
    <div>
      <Layout.field_container>
        <:label align={Backpex.Field.align_label(@field_options, assigns, :top)}>
          <Layout.input_label id={"inline-crud-label-#{@name}"} as="span" text={@field_options[:label]} />
        </:label>

        <div class="flex flex-col">
          <.inputs_for :let={f_nested} field={@form[@name]}>
            <input type="hidden" name={"change[#{@name}_order][]"} value={f_nested.index} tabindex="-1" aria-hidden="true" />

            <div class="mb-3 flex items-start gap-x-4">
              <div
                :for={{child_field_name, child_field_options} <- @child_fields}
                class={child_field_class(child_field_options, assigns)}
              >
                <div
                  :if={f_nested.index == 0}
                  id={"inline-crud-header-label-#{@name}-#{child_field_name}"}
                  class="mb-2 text-xs"
                >
                  {child_field_options.label}
                </div>
                {Backpex.HTML.Resource.resource_form_field(
                  assign(assigns,
                    hide_label: true,
                    aria_labelledby: "inline-crud-label-#{@name} inline-crud-header-label-#{@name}-#{child_field_name}",
                    fields: @child_fields,
                    name: child_field_name,
                    form: f_nested
                  )
                )}
              </div>

              <div class={if f_nested.index == 0, do: "mt-5", else: nil}>
                <label for={"#{@name}-checkbox-delete-#{f_nested.index}"}>
                  <input
                    id={"#{@name}-checkbox-delete-#{f_nested.index}"}
                    type="checkbox"
                    name={"change[#{@name}_delete][]"}
                    value={f_nested.index}
                    class="hidden"
                  />

                  <div class="btn btn-outline btn-error">
                    <span class="sr-only">{Backpex.__("Delete", @live_resource)}</span>
                    <Backpex.HTML.CoreComponents.icon name="hero-trash" class="size-5" />
                  </div>
                </label>
              </div>
            </div>
          </.inputs_for>

          <input type="hidden" name={"change[#{@name}_delete][]"} tabindex="-1" aria-hidden="true" />
        </div>
        <input
          name={"change[#{@name}_order][]"}
          type="checkbox"
          aria-label={Backpex.__("Add entry", @live_resource)}
          class="btn btn-outline btn-sm btn-primary"
        />

        <BackpexForm.error :for={msg <- @errors} class="mt-1">{msg}</BackpexForm.error>

        <%= if help_text = Backpex.Field.help_text(@field_options, assigns) do %>
          <Backpex.HTML.Form.help_text class="mt-1">{help_text}</Backpex.HTML.Form.help_text>
        <% end %>
      </Layout.field_container>
    </div>
    """
  end

  @impl Backpex.Field
  def association?({_name, %{type: :assoc}} = _field), do: true
  def association?({_name, %{type: :embed}} = _field), do: false

  @impl Backpex.Field
  def schema({name, _field_options}, schema) do
    schema.__schema__(:association, name)
    |> Map.get(:queryable)
  end

  defp get_link(assigns, row) do
    live_resource = Map.get(assigns.field_options, :live_resource)

    if live_resource && live_resource.can?(assigns, :show, row) do
      Router.get_path(assigns.socket, live_resource, assigns.params, :show, row)
    end
  end

  defp child_field_class(%{class: class} = _child_field_options, assigns) when is_function(class), do: class.(assigns)
  defp child_field_class(%{class: class} = _child_field_options, _assigns) when is_binary(class), do: class
  defp child_field_class(_child_field_options, _assigns), do: "flex-1"

  defp assign_form_errors(socket) do
    %{assigns: %{form: form, name: name, field_options: field_options}} = socket

    errors = if Phoenix.Component.used_input?(form[name]), do: form[name].errors, else: []
    translate_error_fun = Map.get(field_options, :translate_error, &Function.identity/1)

    assign(socket, :errors, BackpexForm.translate_form_errors(errors, translate_error_fun))
  end
end
