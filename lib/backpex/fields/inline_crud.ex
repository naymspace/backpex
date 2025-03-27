defmodule Backpex.Fields.InlineCRUD do
  @config_schema [
    type: [
      doc: "The type of the field.",
      type: {:in, [:embed, :assoc]},
      required: true
    ],
    child_fields: [
      doc: """
      A list of input fields to be used. Currently only support `Backpex.Fields.Text` fields.

      You can add additional classes to child field inputs by setting the class option in the list of `child_fields`.
      The class can be a string or a function that takes the assigns and must return a string. In addition, you can
      optionally specify the input type of child field inputs with the `input_type` option. We currently support `:text`
      and `:textarea`. The `input_type` defaults to `:text`.
      """,
      type: :keyword_list,
      required: true
    ]
  ]

  @moduledoc """
  A field to handle inline CRUD operations. It can be used with either an `embeds_many` or `has_many` (association) type column.

  ## Field-specific options

  See `Backpex.Field` for general field options.

  #{NimbleOptions.docs(@config_schema)}

  > #### Important {: .info}
  >
  > Everything is currently handled by plain text input.

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

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    socket
    |> assign(assigns)
    |> ok()
  end

  @impl Backpex.Field
  def render_value(assigns) do
    ~H"""
    <div class="ring-base-content/10 rounded-box overflow-x-auto ring-1">
      <table class="table">
        <thead class="bg-base-200/50 text-base-content uppercase">
          <tr>
            <th :for={{_name, %{label: label}} <- @field_options.child_fields} class="font-medium">
              {label}
            </th>
          </tr>
        </thead>
        <tbody class="text-base-content/75">
          <tr :for={row <- @value} class="border-base-content/10 border-b last:border-b-0">
            <td :for={{name, _field_options} <- @field_options.child_fields}>
              {HTML.pretty_value(Map.get(row, name))}
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  @impl Backpex.Field
  def render_form(assigns) do
    assigns =
      assigns
      |> assign(:child_fields, assigns.field_options.child_fields)

    ~H"""
    <div>
      <Layout.field_container>
        <:label align={Backpex.Field.align_label(@field_options, assigns, :top)}>
          <Layout.input_label text={@field_options[:label]} />
        </:label>

        <div class="flex flex-col">
          <.inputs_for :let={f_nested} field={@form[@name]}>
            <input type="hidden" name={"change[#{@name}_order][]"} value={f_nested.index} />

            <div class="mb-3 flex items-start gap-x-4">
              <div
                :for={{child_field_name, child_field_options} <- @child_fields}
                class={child_field_class(child_field_options, assigns)}
              >
                <p :if={f_nested.index == 0} class="mb-1 text-xs">
                  {child_field_options.label}
                </p>
                <BackpexForm.input
                  type={input_type(child_field_options) |> Atom.to_string()}
                  field={f_nested[child_field_name]}
                  translate_error_fun={Backpex.Field.translate_error_fun(child_field_options, assigns)}
                  phx-debounce={Backpex.Field.debounce(child_field_options, assigns)}
                  phx-throttle={Backpex.Field.throttle(child_field_options, assigns)}
                />
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

                  <div class="btn btn-outline btn-error btn-lg" aria-label={Backpex.translate("Delete")}>
                    <Backpex.HTML.CoreComponents.icon name="hero-trash" class="h-5 w-5" />
                  </div>
                </label>
              </div>
            </div>
          </.inputs_for>

          <input type="hidden" name={"change[#{@name}_delete][]"} />
        </div>
        <input
          name={"change[#{@name}_order][]"}
          type="checkbox"
          aria-label={Backpex.translate("Add entry")}
          class="btn btn-outline btn-sm btn-primary"
        />
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

  defp child_field_class(%{class: class} = _child_field_options, assigns) when is_function(class), do: class.(assigns)
  defp child_field_class(%{class: class} = _child_field_options, _assigns) when is_binary(class), do: class
  defp child_field_class(_child_field_options, _assigns), do: "grow"

  defp input_type(%{input_type: input_type} = _child_field_options) when input_type in [:text, :textarea],
    do: input_type

  defp input_type(_child_field_options), do: :text
end
