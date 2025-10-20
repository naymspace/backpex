defmodule Backpex.Fields.InlineCRUD do
  @config_schema [
    type: [
      doc: "The type of the field. One of `:embed`, `:embed_one` or `:assoc`  or `:map`.",
      type: {:in, [:embed, :assoc, :embed_one, :map]},
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
    ],
    validate: [
      doc: """
      An optional validation function used to validate `:map` child fields. It takes the changeset
      and returns a changeset. You can use it to validate the `child_fields`
      of a `map`, see the examples .
      """,
      type: {:fun, 1}
    ]
  ]

  @moduledoc """
  A field to handle inline CRUD operations. It can be used with with columns of type `map`, `embeds_many`, `embeds_one`, or `has_many` (for associations).

  ## Field-specific options

  See `Backpex.Field` for general field options.

  #{NimbleOptions.docs(@config_schema)}

  > #### Important {: .info}
  >
  > Everything is currently handled by plain text input.

  ### EmbedsMany and EmbedsOne

  The field in the migration must be of type `:map`. You also need to use ecto's `cast_embed/2` in the changeset.

  ### Example

      def changeset(your_schema, attrs) do
        your_schema
        ...
        |> cast_embed(:your_field,
          with: &your_field_changeset/2,
          sort_param: :your_field_order, # not required for embeds_one
          drop_param: :your_field_delete # not required for embeds_one
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
  ### Map

  By using the `:map` type you can use the `InlineCRUD` to control waht fields can be stored in a `map`.
  With the `:map` type the InlineCRUD uses the `input_type` option to build out the `types` map needed
  to create a changeset. If the `input_type` is not set, it defaults to `:string`.
  Another option is the `validate` callback that you can add to `fields` settings to
  process the `child_fields` as in the example below.

      @impl Backpex.LiveResource
      def fields do
      [
        model: %{
          module: Backpex.Fields.Text,
          label: "Model",
          searchable: true
        },
        info: %{
          module: Backpex.Fields.InlineCRUD,
          label: "Information",
          type: :map,
          except: [:index],
          child_fields: [
            engine_size: %{
              module: Backpex.Fields.Text,
              label: "Engine Size (cc)",
              input_type: :integer
            },
            colour: %{
              module: Backpex.Fields.Text,
              label: "Colour"
            },
            year: %{
              module: Backpex.Fields.Text,
              label: "Year",
              input_type: :integer
            }
          ],
          validate: fn changeset->
            changeset
            |> Ecto.Changeset.validate_required([:colour, :year])
            |> Ecto.Changeset.validate_number(:year,
                  greater_than: 1900,
                  less_than: Date.utc_today().year + 1,
                  message: "must be between 1900 and #{Date.utc_today().year + 1}"
                  )
          end
        }
      ]
      end

  Then use the function `Backpex.Fields.InlineCRUD.changeset` in your schema's changeset to invoke the `validate` function.
  """

  use Backpex.Field, config_schema: @config_schema
  require Backpex

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    socket
    |> assign(assigns)
    |> ok()
  end

  @impl Backpex.Field
  def render_value(assigns) do
    assigns =
      assigns
      |> assign(
        :value,
        if(assigns[:field_options].type in [:embed_one, :map], do: [get_value(assigns, :value)], else: assigns[:value])
      )

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
              {HTML.pretty_value(Map.get(row, Atom.to_string(name)))}
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
          <Layout.input_label id={"inline-crud-label-#{@name}"} as="span" text={@field_options[:label]} />
        </:label>

        <div class="flex flex-col">
          <%= if @field_options.type != :map do %>
            <.inputs_for :let={f_nested} field={@form[@name]}>
              <input type="hidden" name={"change[#{@name}_order][]"} value={f_nested.index} />

              <div class="mb-3 flex items-start gap-x-4">
                <div
                  :for={{child_field_name, child_field_options} <- @child_fields}
                  class={child_field_class(child_field_options, assigns)}
                >
                  <span
                    :if={f_nested.index == 0}
                    id={"inline-crud-header-label-#{@name}-#{child_field_name}"}
                    class="mb-1 text-xs"
                  >
                    {child_field_options.label}
                  </span>
                  <BackpexForm.input
                    type={input_type(child_field_options) |> Atom.to_string()}
                    field={f_nested[child_field_name]}
                    aria-labelledby={"inline-crud-header-label-#{@name}-#{child_field_name} inline-crud-label-#{@name}"}
                    translate_error_fun={Backpex.Field.translate_error_fun(child_field_options, assigns)}
                    phx-debounce={Backpex.Field.debounce(child_field_options, assigns)}
                    phx-throttle={Backpex.Field.throttle(child_field_options, assigns)}
                  />
                </div>
                <%= if @field_options.type != :embed_one do %>
                  <div class={if f_nested.index == 0, do: "mt-5", else: nil}>
                    <label for={"#{@name}-checkbox-delete-#{f_nested.index}"}>
                      <input
                        id={"#{@name}-checkbox-delete-#{f_nested.index}"}
                        type="checkbox"
                        name={"change[#{@name}_delete][]"}
                        value={f_nested.index}
                        class="hidden"
                      />

                      <div class="btn btn-outline btn-error" aria-label={Backpex.__("Delete", @live_resource)}>
                        <Backpex.HTML.CoreComponents.icon name="hero-trash" class="h-5 w-5" />
                      </div>
                    </label>
                  </div>
                <% end %>
              </div>
            </.inputs_for>
            <%= if @field_options.type != :embed_one do %>
              <input type="hidden" name={"change[#{@name}_delete][]"} />
            <% end %>
          <% else %>
            <div class="mb-3 flex items-start gap-x-4">
              <div
                :for={{child_field_name, child_field_options} <- @child_fields}
                class={child_field_class(child_field_options, assigns)}
              >
                <span
                  id={"inline-crud-header-label-#{@name}-#{child_field_name}"}
                  class="mb-1 text-xs"
                >
                  {child_field_options.label}
                </span>
                <BackpexForm.input
                  id={"change_#{Atom.to_string(@name)}_#{Atom.to_string(child_field_name)}"}
                  type={input_type(child_field_options) |> Atom.to_string()}
                  name={"change[#{Atom.to_string(@name)}][#{Atom.to_string(child_field_name)}]"}
                  value={changeset_value(assigns, child_field_name)}
                  errors={changeset_errors(assigns, child_field_name)}
                  aria-labelledby={"inline-crud-header-label-#{@name}-#{child_field_name} inline-crud-label-#{@name}"}
                  translate_error_fun={Backpex.Field.translate_error_fun(child_field_options, assigns)}
                  phx-debounce={Backpex.Field.debounce(child_field_options, assigns)}
                  phx-throttle={Backpex.Field.throttle(child_field_options, assigns)}
                />
              </div>
            </div>
          <% end %>
          <%= if @field_options.type in [:emded, :assoc] do %>
            <input
              name={"change[#{@name}_order][]"}
              type="checkbox"
              aria-label={Backpex.__("Add entry", @live_resource)}
              class="btn btn-outline btn-sm btn-primary"
            />
          <% end %>

          <%= if help_text = Backpex.Field.help_text(@field_options, assigns) do %>
            <Backpex.HTML.Form.help_text class="mt-1">{help_text}</Backpex.HTML.Form.help_text>
          <% end %>
        </div>
      </Layout.field_container>
    </div>
    """
  end

  @impl Backpex.Field
  def association?({_name, %{type: :assoc}} = _field), do: true
  def association?({_name, %{type: _type}} = _field), do: false

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

  defp get_value(assigns, field) do
    case Map.get(assigns, field, %{}) do
      nil -> %{}
      value -> value
    end
  end

  @doc """
  Use this function to create a changeset for your `:map` within
  your schema's changeset function.  Then you can use the `changeset`
  it returns for the `:map` to validate your map fields in detail.

  ## Parameters

    * `form_changeset`: The `changeset` of your `schema`
    * `map_field`: The name of the map field in your schema
    * `metadata`: The `Backpex` metadata.

  """
  def changeset(form_changeset, map_field, metadata) do
    field_info = get_in(metadata, [:assigns, :fields, map_field])

    if is_nil(field_info) do
      form_changeset
    else
      types =
        field_info[:child_fields]
        |> Map.new(fn {k, settings} ->
          {k, settings |> Map.get(:input_type, :string)}
        end)

      case field_info[:validate] do
        nil ->
          form_changeset

        validator ->
          fields_changeset =
            {%{}, types}
            |> Ecto.Changeset.cast(Ecto.Changeset.get_field(form_changeset, map_field), Map.keys(types))
            |> validator.()

          form_changeset
          |> copy_errors(fields_changeset)
          |> copy_values(fields_changeset)
          |> Ecto.Changeset.put_change(
            map_field,
            values
          )
      end
    end
  end

  def copy_errors(dest_changeset, src_changeset) do
    Enum.reduce(src_changeset.errors, form_changeset, fn {field, error}, form_changeset ->
      {msg, _opts} = error
      Ecto.Changeset.add_error(form_changeset, field, msg)
    end)
  end

  def copy_values(dest_changeset, src_changeset) do
    dest_changeset
    |> Ecto.Changeset.put_change(
      map_field,
      Ecto.Changeset.apply_changes(fields_changeset)
      |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end)
    )
  end

  defp changeset_value(assigns, field) when is_atom(field), do: changeset_value(assigns, Atom.to_string(field))

  defp changeset_value(assigns, field) when is_binary(field) do
    Ecto.Changeset.get_field(assigns.changeset, assigns.name)
    |> Map.get(field)
  end

  defp changeset_errors(assigns, field) when is_binary(field),
    do: changeset_errors(assigns, String.to_existing_atom(field))

  defp changeset_errors(assigns, field) when is_atom(field) do
    for {^field, {error, _opts}} <- assigns.changeset.errors,
        do: error
  end
end
