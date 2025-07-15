# credo:disable-for-this-file Credo.Check.Refactor.CyclomaticComplexity
defmodule Backpex.Field do
  @config_schema [
    module: [
      doc: "The field module.",
      type: :atom,
      required: true
    ],
    label: [
      doc: "The field label.",
      type: :string,
      required: true
    ],
    help_text: [
      doc: "A text to be displayed below the input on form views.",
      type: {:or, [:string, {:fun, 1}]}
    ],
    default: [
      doc: """
      A function to assign default values to fields. Also see the [field defaults](/guides/fields/defaults.md) guide.
      """,
      type: {:fun, 1}
    ],
    render: [
      doc: "A function to overwrite the template used . It should take `assigns` and return a HEEX template.",
      type: {:fun, 1}
    ],
    render_form: [
      doc: "A function to overwrite the template used in forms. It should take `assigns` and return a HEEX template.",
      type: {:fun, 1}
    ],
    custom_alias: [
      doc: "A custom alias for the field.",
      type: :atom
    ],
    align: [
      doc: "Align the fields of a resource in the index view.",
      type: {:in, [:left, :center, :right]}
    ],
    align_label: [
      doc: "Align the labels of the fields in the edit view.",
      type: {:or, [{:in, [:top, :center, :bottom]}, {:fun, 1}]}
    ],
    searchable: [
      doc: "Define wether this field should be searchable on the index view.",
      type: :boolean
    ],
    orderable: [
      doc: "Define wether this field should be orderable on the index view.",
      type: :boolean
    ],
    visible: [
      doc:
        "Function to change the visibility of a field for all views except index. Receives the assigns and has to return a boolean.",
      type: {:fun, 1}
    ],
    can?: [
      doc:
        "Function to change the visibility of a field for all views. Receives the assigns and has to return a boolean.",
      type: {:fun, 1}
    ],
    panel: [
      doc: "Group field into panel. Also see the [panels](/guides/authorization/panels.md) guide.",
      type: :atom
    ],
    index_editable: [
      doc: """
      Define wether this field should be editable on the index view. Also see the
      [index edit](/guides/authorization/index-edit.md) guide.
      """,
      type: {:or, [:boolean, {:fun, 1}]}
    ],
    index_column_class: [
      doc: """
      Add additional class(es) to the index column.
      In case of a function it takes the `assigns` and should return a string.
      """,
      type: {:or, [:string, {:fun, 1}]}
    ],
    select: [
      doc: """
      Define a dynamic select query expression for this field.

      ### Example

          full_name: %{
            module: Backpex.Fields.Text,
            label: "Full Name",
            select: dynamic([user: u], fragment("concat(?, ' ', ?)", u.first_name, u.last_name)),
          }
      """,
      type: {:struct, Ecto.Query.DynamicExpr}
    ],
    only: [
      doc: "Define the only views where this field should be visible.",
      type: {:list, {:in, [:new, :edit, :show, :index, :resource_action]}}
    ],
    except: [
      doc: "Define the views where this field should not be visible.",
      type: {:list, {:in, [:new, :edit, :show, :index, :resource_action]}}
    ],
    translate_error: [
      doc: """
      Function to customize error messages for a field. The function receives the error tuple and must return a tuple
      with the message and metadata.
      """,
      type: {:fun, 1}
    ]
  ]

  @moduledoc """
  Behaviour implemented by all fields.

  A field defines how a column is rendered on index, show and edit views. In the resource configuration file you can
  configure a list of fields. You may create your own field by implementing this behaviour. A field has to be a
  [LiveComponent](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveComponent.html).

  ### Options

  These are general field options which can be used on every field. Check the field modules for field-specific options.

  #{NimbleOptions.docs(@config_schema)}

  ### Example

      def fields do
        [
          rating: %{
            module: Backpex.Fields.Text,
            label: "Rating"
          }
        ]
      end
  """
  import Phoenix.Component, only: [assign: 3]

  @doc """
  Will be used on index and show views to render a value from the provided item. This has to be a heex template.
  """
  @callback render_value(assigns :: map()) :: %Phoenix.LiveView.Rendered{}

  @doc """
  Will be used on edit views to render a form for the value of the provided item. This has to be a heex template.
  """
  @callback render_form(assigns :: map()) :: %Phoenix.LiveView.Rendered{}

  @doc """
  Used to render form on index to support index editable.
  """
  @callback render_index_form(assigns :: map()) :: %Phoenix.LiveView.Rendered{}

  @doc """
  Used to render the readonly version of the field.
  """
  @callback render_form_readonly(assigns :: map()) :: %Phoenix.LiveView.Rendered{}

  @doc """
  The field to be displayed on index views. In most cases this is the name / key configured in the corresponding field definition.
  In fields with associations this value often differs from the name / key. The function will receive the field definition.
  """
  @callback display_field(field :: tuple()) :: atom()

  @doc """
  The schema to be used in queries. In most cases this is the schema defined in the resource configuration.
  In fields with associations this is the schema of the corresponding relation. The function will receive the field definition and the schema defined in the resource configuration.
  """
  @callback schema(field :: tuple(), schema :: atom()) :: atom()

  @doc """
  Determines whether the field is an association or not.
  """
  @callback association?(field :: tuple()) :: boolean()

  @doc """
  This function will be called in the `FormComponent` and may be used to assign uploads.
  """
  @callback assign_uploads(field :: tuple(), socket :: Phoenix.LiveView.Socket.t()) ::
              Phoenix.LiveView.Socket.t()

  @doc """
  This function is called before the changeset function is called. This allows fields to modify the changeset.
  The `Backpex.Fields.HasMany` uses this callback to put the linked associations into the changeset.
  """
  @callback before_changeset(
              changeset :: Phoenix.LiveView.Socket.t(),
              attrs :: map(),
              metadata :: keyword(),
              repo :: module(),
              field :: tuple(),
              assigns :: map()
            ) :: Ecto.Changeset.t()

  @doc """
  Defines the search condition. Defaults to an ilike condition with text comparison. The function has to return a query wrapped into a `Ecto.Query.dynamic/2` which is then passed into a `Ecto.Query.where/3`.

  ## Example

  Imagine the underlying database type of the field is an integer. Before text comparison in an ilike condition you have to cast the integer to text.

  The function could return the following query to make the field searchable.

      dynamic(
        [{^schema_name, schema_name}],
        ilike(fragment("CAST(? AS TEXT)", schema_name |> field(^field_name)), ^search_string)
      )
  """
  @callback search_condition(
              schema_name :: binary(),
              field_name :: binary(),
              search_string :: binary()
            ) ::
              Ecto.Query.dynamic_expr()

  @optional_callbacks render_form_readonly: 1, render_index_form: 1

  @doc """
  Returns the default config schema.
  """
  def default_config_schema, do: @config_schema

  @doc """
  Defines `Backpex.Field` behaviour and provides default implementations.
  """
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @config_schema opts[:config_schema] || []

      @before_compile Backpex.Field
      @behaviour Backpex.Field

      use BackpexWeb, :field

      @doc """
      Returns the schema of configurable options for this field.

      This can be useful for reuse in other field modules.
      """
      def config_schema, do: @config_schema

      @doc false
      def validate_config!({name, options} = _field, live_resource) do
        field_options = Keyword.new(options)

        case NimbleOptions.validate(field_options, Backpex.Field.default_config_schema() ++ @config_schema) do
          {:ok, validated_options} ->
            validated_options

          {:error, error} ->
            raise """
            Configuration error for field "#{name}" in "#{live_resource}".

            #{error.message}
            """
        end
      end
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      import Ecto.Query

      @impl Phoenix.LiveComponent
      def render(%{type: :index} = assigns) do
        if Backpex.Field.index_editable_enabled?(assigns.field_options, assigns) do
          case Map.get(assigns.field_options, :render_index_form) do
            nil ->
              apply(__MODULE__, :render_index_form, [assigns])

            func ->
              func.(assigns)
          end
        else
          Map.get(assigns.field_options, :render, &render_value/1).(assigns)
        end
      end

      @impl Phoenix.LiveComponent
      def render(%{type: :form} = assigns) do
        if Backpex.Field.readonly?(assigns.field_options, assigns) do
          case Map.get(assigns.field_options, :render_form_readonly) do
            nil ->
              apply(__MODULE__, :render_form_readonly, [assigns])

            func ->
              func.(assigns)
          end
        else
          Map.get(assigns.field_options, :render_form, &render_form/1).(assigns)
        end
      end

      @impl Backpex.Field
      def display_field({name, _field_options} = _field), do: name

      @impl Backpex.Field
      def schema(_field, schema), do: schema

      @impl Backpex.Field
      def association?(_field), do: false

      @impl Backpex.Field
      def assign_uploads(_field, socket), do: socket

      @impl Backpex.Field
      def search_condition(schema_name, field_name, search_string) do
        dynamic(
          [{^schema_name, schema_name}],
          ilike(schema_name |> field(^field_name), ^search_string)
        )
      end

      @impl Backpex.Field
      def before_changeset(changeset, _attrs, _metadata, _repo, _field, _assigns), do: changeset
    end
  end

  @doc """
  Checks whether index editable is enabled or not.
  """
  def index_editable_enabled?(field_options, assigns, default \\ false)

  def index_editable_enabled?(_field_options, %{live_action: live_action}, _default)
      when live_action != :index do
    false
  end

  def index_editable_enabled?(%{index_editable: index_editable}, _assigns, _default) when is_boolean(index_editable),
    do: index_editable

  def index_editable_enabled?(%{index_editable: index_editable}, assigns, _default) when is_function(index_editable),
    do: index_editable.(assigns)

  def index_editable_enabled?(_field_options, _assigns, default), do: default

  @doc """
  Defines placeholder value.
  """
  def placeholder(%{placeholder: placeholder}, _assigns) when is_binary(placeholder), do: placeholder
  def placeholder(%{placeholder: placeholder}, assigns) when is_function(placeholder, 1), do: placeholder.(assigns)
  def placeholder(_field, _assigns), do: nil

  def help_text(%{help_text: help_text}, _assigns) when is_binary(help_text), do: help_text
  def help_text(%{help_text: help_text}, assigns) when is_function(help_text, 1), do: help_text.(assigns)
  def help_text(_field, _assigns), do: nil

  @doc """
  Defines debounce timeout value.
  """
  def debounce(%{debounce: debounce}, _assigns) when is_binary(debounce) or is_integer(debounce), do: debounce
  def debounce(%{debounce: debounce}, assigns) when is_function(debounce, 1), do: debounce.(assigns)
  def debounce(_field, _assigns), do: nil

  @doc """
  Defines throttle timeout value.
  """
  def throttle(%{throttle: throttle}, _assigns) when is_binary(throttle) or is_integer(throttle), do: throttle
  def throttle(%{throttle: throttle}, assigns) when is_function(throttle, 1), do: throttle.(assigns)
  def throttle(_field, _assigns), do: nil

  @doc """
  Determines whether the field should be rendered as readonly version.
  """
  def readonly?(%{readonly: readonly}, _assigns) when is_boolean(readonly), do: readonly
  def readonly?(%{readonly: readonly}, assigns) when is_function(readonly, 1), do: readonly.(assigns)
  def readonly?(_field_options, _assigns), do: false

  def translate_error_fun(%{translate_error: translate_error}, _assigns) when is_function(translate_error, 1),
    do: translate_error

  def translate_error_fun(_field_options, _assigns), do: &Function.identity/1

  @doc """
  Gets alignment option for label.
  """
  def align_label(field_options, assigns, default \\ :center)

  def align_label(%{align_label: align_label}, _assigns, default) when is_atom(align_label) do
    align_label
    |> get_align_label(default)
  end

  def align_label(%{align_label: align_label}, assigns, default) when is_function(align_label) do
    assigns
    |> align_label.()
    |> get_align_label(default)
  end

  def align_label(_field_options, _assigns, default) do
    default
  end

  defp get_align_label(align_label, _default) when align_label in [:top, :center, :bottom] do
    align_label
  end

  defp get_align_label(_align_label, default) do
    default
  end

  @doc """
  Returns a map of types from a list of fields used for the Ecto changeset.
  """
  def changeset_types(fields) do
    fields
    |> Enum.map(fn {name, field_options} ->
      {name, field_options.type}
    end)
    |> Enum.into(%{})
  end

  @doc """
  Handles index editable.
  """
  def handle_index_editable(socket, value, change) do
    %{assigns: %{item: item, live_resource: live_resource, fields: fields} = assigns} = socket

    if not live_resource.can?(assigns, :edit, item) do
      raise Backpex.ForbiddenError
    end

    opts = [
      after_save_fun: fn item ->
        live_resource.on_item_updated(socket, item)

        {:ok, item}
      end
    ]

    result = Backpex.Resource.update(item, change, fields, assigns, live_resource, opts)

    socket =
      case result do
        {:ok, _item} ->
          assign(socket, :valid, true)

        _error ->
          assign(socket, :valid, false)
      end
      |> assign(:form, Phoenix.Component.to_form(%{"value" => value}, as: :index_form))

    {:noreply, socket}
  end
end
