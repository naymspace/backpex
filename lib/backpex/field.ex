# credo:disable-for-this-file Credo.Check.Refactor.CyclomaticComplexity
defmodule Backpex.Field do
  @moduledoc ~S'''
  Behaviour implemented by all fields.

  A field defines how a column is rendered on index, show and edit views. In the resource configuration file you can configure a list of fields. You may create your own field by implementing this behaviour. A field has to be a [LiveComponent](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveComponent.html).

  ### Example

      def fields do
        [
          rating: %{
            module: Backpex.Fields.Text,
            label: "Rating"
          }
        ]
      end
  '''
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
  Defines `Backpex.Field` behaviour and provides default implementations.
  """
  defmacro __using__(_) do
    quote do
      @before_compile Backpex.Field
      @behaviour Backpex.Field
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
  def placeholder(%{placeholder: placeholder}, assigns) when is_function(placeholder), do: placeholder.(assigns)
  def placeholder(_field, _assigns), do: nil

  @doc """
  Defines debounce timeout value.
  """
  def debounce(%{debounce: debounce}, _assigns) when is_binary(debounce) or is_integer(debounce), do: debounce
  def debounce(%{debounce: debounce}, assigns) when is_function(debounce), do: debounce.(assigns)
  def debounce(_field, _assigns), do: nil

  @doc """
  Defines throttle timeout value.
  """
  def throttle(%{throttle: throttle}, _assigns) when is_binary(throttle) or is_integer(throttle), do: throttle
  def throttle(%{throttle: throttle}, assigns) when is_function(throttle), do: throttle.(assigns)
  def throttle(_field, _assigns), do: nil

  @doc """
  Determines whether the field should be rendered as readonly version.
  """
  def readonly?(%{readonly: readonly}, _assigns) when is_boolean(readonly), do: readonly
  def readonly?(%{readonly: readonly}, assigns) when is_function(readonly), do: readonly.(assigns)
  def readonly?(_field_options, _assigns), do: false

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
    if not Backpex.LiveResource.can?(socket.assigns, :edit, socket.assigns.item, socket.assigns.live_resource) do
      raise Backpex.ForbiddenError
    end

    %{
      assigns:
        %{
          repo: repo,
          item: item,
          pubsub: pubsub,
          changeset_function: changeset_function,
          live_resource: live_resource
        } = assigns
    } = socket

    opts = [
      pubsub: pubsub,
      assigns: assigns,
      after_save: fn item ->
        live_resource.on_item_updated(socket, item)

        {:ok, item}
      end
    ]

    result = Backpex.Resource.update(item, change, repo, changeset_function, opts)

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
