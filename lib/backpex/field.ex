# credo:disable-for-this-file Credo.Check.Refactor.CyclomaticComplexity
defmodule Backpex.Field do
  @moduledoc ~S'''
  Behaviour implemented by all fields.

  A field defines how a column is rendered on index, show and edit views. In the resource configuration file you can configure
  a list of fields. You may create your own field by implementing this behaviour. A field has to be a [LiveComponent](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveComponent.html).

  When creating your own field, you can use the `field` macro from the `BackpexWeb` module. It automatically implements the `Backpex.Field` behaviour
  and defines some aliases and imports.

  The simplest version of a custom field would look like this:

      use BackpexWeb, :field

      @impl Backpex.Field
      def render_value(assigns) do
        ~H"""
        <p>
          <%= HTML.pretty_value(@value) %>
        </p>
        """
      end

      @impl Backpex.Field
      def render_form(assigns) do
        ~H"""
        <div>
          <Layout.field_container>
            <:label>
              <Layout.input_label text={@field_options[:label]} />
            </:label>
            <BackpexForm.field_input type="text" form={@form} field_name={@name} field_options={@field_options} />
          </Layout.field_container>
        </div>
        """
      end

  The `render_value/1` function returns markup that is used to display a value on `index` and `show` views.
  The `render_form/1` function returns markup that is used to render a form on `edit` and `new` views.

  The list of fields in the resource configuration has to be a keyword list. The key has to be the name of the column.
  The value has to be a list of options represented as a map. At least you are required to provide the module of the field and a label as options.
  For extra information and options you may have to look into the corresponding field documentation.

  ### Example

      def fields do
        [
          rating: %{
            module: Backpex.Fields.Text,
            label: "Rating"
          }
        ]
      end

  ## Read-only fields

  Fields can be configured to be read-only. In edit view, these fields are rendered with the additional HTML attributes `readonly` and `disabled`,
  ensuring that the user cannot interact with the field or change its value.

  In index view, if read-only and index editable are set to `true`, forms will be rendered with the `readonly` HTML attribute.

  Currently read-only configuration is possible for `Backpex.Fields.Text` and `Backpex.Fields.Textarea` on edit view.

  On the index view, read-only is supported for all fields with the index editable option.

  You can also add read-only functionality to a custom field. To do this, you need to define a `render_form_readonly/1` function.
  This function must return markup to be used when read-only is enabled.

      @impl Backpex.Field
      def render_form_readonly(assigns) do
        ~H"""
        <div>
          <Layout.field_container>
            <:label>
              <Layout.input_label text={@field[:label]} />
            </:label>
            <BackpexForm.field_input
              type="text"
              form={@form}
              field_name={@name}
              field_options={@field_options}
              readonly
              disabled
            />
          </Layout.field_container>
        </div>
        """
      end

  When defining a custom field with index editable support, you need to handle the read-only state in the index editable markup.
  We pass a `readonly` value to index fields, which will be `true` or `false` depending on the read-only option of the field and the `can?/3` function.

  Fields can be set to read-only in the configuration map of the field by adding the `readonly` option. This key must
  contain either a boolean value or a function that returns a boolean value.

  The function takes `assigns` as a parameter. This allows the field to be set as read-only programmatically, as the
  following example illustrates:

      rating: %{
        module: Backpex.Fields.Text,
        label: "Rating",
        readonly: fn assigns ->
          assigns.current_user.role in [:employee]
        end
      }

  ## Computed Fields

  Sometimes you want to compute new fields based on existing fields.

  Imagine there is a user table with `first_name` and `last_name`. Now, on your index view you want to add a column to display
  the `full_name`. You could create a generated column in you database, but there are several reasons for not adding generated
  columns for all computed fields you want to display in your application.

  Backpex adds a way to support this.

  There is a `select` option you may add to a field. This option has to return a `dynamic`. This query will then be executed to
  select fields when listing your resources. In addition this query will also be used to order / search this field.

  Therefore you can display the `full_name` of your users by adding the following field to the resource configuration file.

      full_name: %{
        module: Backpex.Fields.Text,
        label: "Full Name",
        searchable: true,
        except: [:edit],
        select: dynamic([user: u], fragment("concat(?, ' ', ?)", u.first_name, u.last_name))
      }

  We are using a database fragment to build the `full_name` based on the `first_name` and `last_name` of an user. Backpex will select this field when listing resources automatically.
  Ordering and searching works the same like on all other fields, because Backpex uses the query you provided in the `dynamic` in order / search queries, too.

  We recommend to display this field on `index` and `show` view only.

  > Note: You are required to add a virtual field `full_name` to your user schema. Otherwise, Backpex is not able to select this field.

  Computed fields also work in associations.

  For example, you are able to add a `select` query to a `BelongsTo` field.

  Imagine you want to display a list of posts with the corresponding authors (users). The user column should be a `full_name` computed by the `first_name` and `last_name`:

      user: %{
        module: Backpex.Fields.BelongsTo,
        label: "Full Name",
        display_field: :full_name,
        select: dynamic([user: u], fragment("concat(?, ' ', ?)", u.first_name, u.last_name)),
        options_query: fn query, _assigns ->
          query |> select_merge([user], %{full_name: fragment("concat(?, ' ', ?)", user.first_name, user.last_name)})
        end
      }

  We recommend to add a `select_merge` to the `options_query` where you select the same field. Otherwise, displaying the same values in the select form on edit page will not work.

  Do not forget to add the virtual field `full_name` to your user schema in this example, too.

  ## Error Customisation

  Each field can define a `translate_error/1` function to use custom error messages. The function is called for each error and must return a tuple with a message and metadata.

  For example, if you want to indicate that an integer input must be a number:

      number: %{
        module: Backpex.Fields.Number,
        label: "Number",
        translate_error: fn
          {_msg, [type: :integer, validation: :cast] = metadata} = _error ->
            {"has to be a number", metadata}

          error ->
            error
        end
      }
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
  def handle_index_editable(socket, change) do
    if not Backpex.LiveResource.can?(socket.assigns, :edit, socket.assigns.item, socket.assigns.live_resource) do
      raise Backpex.ForbiddenError
    end

    %{assigns: %{item: item} = assigns} = socket

    result =
      assigns
      |> assign(:changeset, item)
      |> Backpex.Resource.update(change)

    socket =
      case result do
        {:ok, _item} -> assign(socket, :valid, true)
        _error -> assign(socket, :valid, false)
      end

    {:noreply, socket}
  end
end
