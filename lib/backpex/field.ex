# credo:disable-for-this-file Credo.Check.Refactor.CyclomaticComplexity
# quokka:skip-module-directive-reordering
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
    readonly: [
      doc: "Sets the field to readonly. Also see the [readonly](/guides/fields/readonly.md) guide.",
      type: {:or, [:boolean, {:fun, 1}]},
      default: false
    ],
    class: [
      type: {:or, [:string, {:fun, 1}]},
      doc: """
      Class or classes to be applied when the field is used as a child field in `Backpex.Fields.InlineCRUD`. The class
      can be a string or a function that takes the assigns and must return a string.
      """
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
    align: [
      doc: "Align the field value on index views.",
      type: {:in, [:left, :center, :right]}
    ],
    align_label: [
      doc: "Align the label of the field on form views.",
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
    order_nulls: [
      doc: """
      Where `NULL` values are placed when the index view is ordered by this field: `:default` (database default),
      `:first` (`NULLS FIRST`), `:last` (`NULLS LAST`) or `:smallest` (`ASC NULLS FIRST` and `DESC NULLS LAST`).
      Overrides the `:order_nulls` option of the LiveResource. See the [Ordering](/guides/live_resource/ordering.md)
      guide.
      """,
      type: {:in, [:default, :first, :last, :smallest]}
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
    only: [
      doc: "Define the only views where this field should be visible.",
      type: {:list, {:in, [:new, :edit, :show, :index]}}
    ],
    except: [
      doc: "Define the views where this field should not be visible.",
      type: {:list, {:in, [:new, :edit, :show, :index]}}
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
  The adapter of the LiveResource may add options, see
  `c:Backpex.Adapter.field_config_schema/0`.

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

  alias Phoenix.LiveView.Rendered
  alias Phoenix.LiveView.Socket

  @doc """
  Will be used on index and show views to render a value from the provided item. This has to be a heex template.
  """
  @callback render_value(assigns :: map()) :: %Rendered{}

  @doc """
  Will be used on edit views to render a form for the value of the provided item. This has to be a heex template.
  """
  @callback render_form(assigns :: map()) :: %Rendered{}

  @doc """
  Used to render form on index to support index editable.
  """
  @callback render_index_form(assigns :: map()) :: %Rendered{}

  @doc """
  Returns assigns for the field on the index view, loaded once for all items of the page.

  Backpex calls it whenever the items of the index view change (e.g. when loading a page, filtering or on item
  events) and merges the returned map into the assigns of the field in every row. It receives the field, the items of
  the page and the assigns of the index view. Use it to load data the field needs, such as the select options of
  `c:render_index_form/1`, with a constant number of queries instead of one query per row and render. Data that differs
  per row can be returned keyed by the item, e.g. by its primary value.

  Also see the [index edit](/guides/fields/index-edit.md#loading-data-for-all-rows-at-once) guide.
  """
  @callback index_assigns(field :: tuple(), items :: list(), assigns :: map()) :: map()

  @doc """
  Returns the change that saves the `value` of an inline edit on the index view, e.g. `%{title: "New title"}`.

  The index view only saves inline edits of fields that implement this callback. It calls it when an index form
  rendered with `Backpex.HTML.Form.index_form/1` changes. It receives the field, the value and the assigns of the index
  view. Validate or normalize the value here, as the index view saves the returned change with the update changeset of
  the LiveResource. Return `:error` to refuse the value, which the index view then marks as invalid.
  """
  @callback index_editable_change(field :: tuple(), value :: any(), assigns :: map()) :: map() | :error

  @doc """
  The field to be displayed on index views. In most cases this is the name / key configured in the corresponding field definition.
  In fields with associations this value often differs from the name / key. The function will receive the field definition.
  """
  @callback display_field(field :: tuple()) :: atom()

  @doc """
  Determines whether the field is an association or not.
  """
  @callback association?(field :: tuple()) :: boolean()

  @doc """
  Returns the condition an item matches when the search of the index view finds it by this field, as an expression
  (see `Backpex.Expr`). Without it, an item matches when the value the field shows contains the search term, ignoring
  the case.

  Receives the field, the `Backpex.Expr.Ref` of the value the field shows (see `Backpex.LiveResource.field_ref/1`) and
  the search term as the user typed it. A condition of the database, e.g. on a formatted date, is a native expression
  of the adapter, see `Backpex.Expr.native/3`:

      import Backpex.Expr

      @impl Backpex.Field
      def search_condition(_field, ref, term), do: expr(starts_with(ref(^ref.path, ^ref.name), ^term))

      @impl Backpex.Field
      def search_condition(_field, %{path: [], name: name}, term) do
        native(
          Backpex.Adapters.Ecto,
          dynamic([item], ilike(fragment("to_char(?, 'DD.MM.YYYY')", field(item, ^name)), ^"%\#{term}%"))
        )
      end
  """
  @callback search_condition(field :: tuple(), ref :: Backpex.Expr.Ref.t(), term :: String.t()) :: Backpex.Expr.t()

  @doc """
  This function will be called in the `FormComponent` and may be used to assign uploads.
  """
  @callback assign_uploads(field :: tuple(), socket :: Socket.t()) ::
              Socket.t()

  @doc """
  This function is called before the changeset function is called. This allows fields to modify the changeset.
  The `Backpex.Fields.HasMany` uses this callback to put the linked associations into the changeset.
  """
  @callback before_changeset(
              changeset :: Ecto.Changeset.t(),
              attrs :: map(),
              metadata :: keyword(),
              field :: tuple(),
              assigns :: map()
            ) :: Ecto.Changeset.t()

  @doc """
  Returns the files of the item as a list of strings.

  Upload fields (see `upload_key/1`) implement it, together with `c:put_upload_change/7`,
  `c:consume_upload/5` and `c:remove_uploads/4`. The form component calls them on the module of the field and passes
  the field, so a custom upload field can implement them once and work out what it needs from the field, such as the
  column to read the files from, instead of taking a function per field as an option. `Backpex.Fields.Upload`
  implements them by calling the functions given in its options.
  """
  @callback list_existing_files(field :: tuple(), item :: struct() | map()) :: [String.t()]

  @doc """
  Puts the files of an upload field into the params that are passed to the changeset function.

  The form component calls it on every change (`action` is `:validate`) and before saving (`action` is `:insert`).
  `uploaded_entries` is the tuple of completed and in progress entries from `Phoenix.LiveView.uploaded_entries/2`,
  `removed_entries` the files the user removed during an edit. See `c:list_existing_files/2`.
  """
  @callback put_upload_change(
              field :: tuple(),
              socket :: Socket.t(),
              params :: map(),
              item :: struct() | map(),
              uploaded_entries :: {list(), list()},
              removed_entries :: [String.t()],
              action :: :validate | :insert
            ) :: map()

  @doc """
  Consumes an uploaded entry after the item has been saved.

  The form component calls it for every entry as the callback of `Phoenix.LiveView.consume_uploaded_entries/3`, with
  the saved item. See `c:list_existing_files/2`.
  """
  @callback consume_upload(
              field :: tuple(),
              socket :: Socket.t(),
              item :: struct(),
              meta :: map(),
              entry :: Phoenix.LiveView.UploadEntry.t()
            ) :: {:ok, term()} | {:postpone, term()}

  @doc """
  Removes the files the user removed during an edit, after the item has been saved.

  The form component calls it with the saved item, so the item already has the changes of the edit. See
  `c:list_existing_files/2`.
  """
  @callback remove_uploads(field :: tuple(), socket :: Socket.t(), item :: struct(), removed_entries :: [String.t()]) ::
              term()

  @doc """
  Returns the text of an upload error, which the form shows next to the file or below the upload.

  `error` is an error from `Phoenix.Component.upload_errors/1` or `Phoenix.Component.upload_errors/2`, such as
  `:too_large` or the `{:external_metadata_failure, meta}` of an `external` function that returned
  `{:error, meta, socket}`. `upload` is the `Phoenix.LiveView.UploadConfig`, for limits such as `max_file_size`, and
  `assigns` are the assigns of `c:render_form/1`. The text is shown as it is returned, so translate it, for example
  with `Backpex.translate_error/1` like the errors of the changeset.

  `Backpex.Fields.Upload` implements it with texts of its own and calls it on the module of the field, so a custom
  upload field that delegates `c:render_form/1` to `Backpex.Fields.Upload` can give its own texts. A field without
  this callback gets the texts of `Backpex.Fields.Upload`. The callback gets every error, so delegate the errors your
  field doesn't handle to `Backpex.Fields.Upload.upload_error/4`, as in the example.

  ## Example

      @impl Backpex.Field
      def upload_error(_field, :too_large, upload, _assigns) do
        Backpex.translate_error({"must be at most %{count} bytes", count: upload.max_file_size})
      end

      def upload_error(field, error, upload, assigns) do
        Backpex.Fields.Upload.upload_error(field, error, upload, assigns)
      end
  """
  @callback upload_error(
              field :: tuple(),
              error :: term(),
              upload :: Phoenix.LiveView.UploadConfig.t(),
              assigns :: map()
            ) :: String.t()

  @optional_callbacks render_index_form: 1,
                      search_condition: 3,
                      index_assigns: 3,
                      index_editable_change: 3,
                      list_existing_files: 2,
                      put_upload_change: 7,
                      consume_upload: 5,
                      remove_uploads: 4,
                      upload_error: 4

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
      def validate_config!({name, options} = _field, live_resource, adapter_schema \\ []) do
        field_options = Keyword.new(options)
        schema = Backpex.Field.default_config_schema() ++ adapter_schema ++ @config_schema

        case NimbleOptions.validate(field_options, schema) do
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

  defmacro __before_compile__(env) do
    # Backpex no longer calls `before_changeset/6`, so a field that still defines it would silently lose its changes.
    if Module.defines?(env.module, {:before_changeset, 6}, :def) do
      raise CompileError,
        file: env.file,
        description: """
        #{inspect(env.module)} defines before_changeset/6, but the callback no longer receives the repo. Implement \
        before_changeset/5 instead, see the guide on upgrading to v0.24.
        """
    end

    quote generated: true do
      @impl Phoenix.LiveComponent
      def render(%{type: :index} = assigns) do
        if Backpex.Field.index_editable_enabled?(assigns.field_options, assigns) do
          case Map.get(assigns.field_options, :render_index_form) do
            fun when is_function(fun, 1) -> fun.(assigns)
            nil -> apply(__MODULE__, :render_index_form, [assigns])
          end
        else
          Map.get(assigns.field_options, :render, &render_value/1).(assigns)
        end
      end

      @impl Phoenix.LiveComponent
      def render(%{type: :form} = assigns) do
        case Map.get(assigns.field_options, :render_form) do
          fun when is_function(fun, 1) -> fun.(assigns)
          nil -> apply(__MODULE__, :render_form, [assigns])
        end
      end

      @impl Backpex.Field
      def display_field({name, _field_options} = _field), do: name

      @impl Backpex.Field
      def association?(_field), do: false

      @impl Backpex.Field
      def assign_uploads(_field, socket), do: socket

      @impl Backpex.Field
      def before_changeset(changeset, _attrs, _metadata, _field, _assigns), do: changeset
    end
  end

  @doc """
  Checks whether index editable is enabled or not.
  """
  def index_editable_enabled?(field_options, assigns, default \\ false)

  def index_editable_enabled?(_field_options, %{live_action: live_action}, _default)
      when live_action not in [:index, :resource_action] do
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

  @doc """
  Returns the module that implements the upload callbacks of an upload field.

  This is the module of the field when it implements `c:consume_upload/5` and the other upload callbacks, otherwise
  `Backpex.Fields.Upload`, which calls the `:list_existing_files`, `:put_upload_change`, `:consume_upload` and
  `:remove_uploads` functions of the field options. So a custom field that only defines an `:upload_key` and these
  options, as before the callbacks existed, keeps working.

  ## Examples

      iex> Backpex.Field.upload_module({:avatar, %{module: Backpex.Fields.Upload}})
      Backpex.Fields.Upload
      iex> Backpex.Field.upload_module({:avatar, %{module: Backpex.Fields.Text}})
      Backpex.Fields.Upload
  """
  @spec upload_module(tuple()) :: module()
  def upload_module({_name, %{module: module}} = _field) do
    if upload_callbacks?(module), do: module, else: Backpex.Fields.Upload
  end

  @doc false
  def upload_callbacks?(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :consume_upload, 5)
  end

  @doc """
  Returns the name of the upload of an upload field, or `nil` for any other field.

  An upload field is a field with an `:upload_key` option, which names its upload, or a field whose module implements
  the upload callbacks, such as `c:consume_upload/5`. The upload of such a field is named after the field when the
  option isn't given.

  ## Examples

      iex> Backpex.Field.upload_key({:avatar, %{module: Backpex.Fields.Upload}})
      :avatar
      iex> Backpex.Field.upload_key({:avatar, %{module: Backpex.Fields.Upload, upload_key: :picture}})
      :picture
      iex> Backpex.Field.upload_key({:avatar, %{module: Backpex.Fields.Text, upload_key: :picture}})
      :picture
      iex> Backpex.Field.upload_key({:title, %{module: Backpex.Fields.Text}})
      nil
  """
  @spec upload_key(tuple()) :: atom() | nil
  def upload_key({name, %{module: module} = field_options}) do
    cond do
      key = Map.get(field_options, :upload_key) -> key
      upload_callbacks?(module) -> name
      true -> nil
    end
  end

  def upload_key(_field), do: nil

  @doc """
  Drops readonly field changes from the given change map.

  Takes a map of string-keyed form params, a keyword list of field definitions,
  and assigns. Returns the change map with readonly field keys removed.
  """
  def drop_readonly_changes(change, fields, assigns) do
    read_only =
      fields
      |> Enum.filter(fn {_name, options} -> readonly?(options, assigns) end)
      |> Enum.map(fn {name, _options} -> Atom.to_string(name) end)

    Map.drop(change, read_only)
  end

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
    Map.new(fields, fn {name, field_options} ->
      {name, field_options.type}
    end)
  end

  @doc """
  Assigns the `:form` and `:valid` assigns of an index form.

  The form holds the value of the item, or the value of an inline edit the index view could not save, which is then
  also marked as invalid. Call it in `c:render_index_form/1` before rendering `Backpex.HTML.Form.index_form/1`.
  """
  def assign_index_form(assigns) do
    {value, valid} =
      case Map.get(assigns, :index_edit) do
        %{value: value, valid: valid} -> {value, valid}
        _index_edit -> {assigns.value, true}
      end

    assigns
    |> assign(:form, Phoenix.Component.to_form(%{"value" => value}, as: :index_form))
    |> assign(:valid, valid)
  end

  @doc """
  Handles index editable in the field component.

  Index forms rendered with `Backpex.HTML.Form.index_form/1` of fields that implement `c:index_editable_change/3` are
  saved by the index view instead, with all of its assigns. This function saves the change with the assigns of the
  field component. With a list of `:context_assigns`, these only include the listed assigns, see the
  `:context_assigns` option of `Backpex.LiveResource`.

  The change is not saved if the field is not index editable or readonly, if the user may not edit the item, or while
  a resource action is open, as the adapter would use the changeset of the resource action. The value is then kept in
  the form and marked as invalid.
  """
  def handle_index_editable(socket, value, change) do
    %{assigns: %{field_options: field_options, item: item, live_resource: live_resource} = assigns} = socket

    # A component rendered outside of a LiveResource, e.g. by `Backpex.HTML.Resource.resource_index_table/1` in a
    # LiveView of your own, may have no `:live_action`. `Backpex.Resource.update/6` enforces `:edit` as well, but would
    # raise.
    if Map.get(assigns, :live_action, :index) == :index && index_editable_enabled?(field_options, assigns) &&
         !readonly?(field_options, assigns) && Backpex.Authorization.can?(live_resource, assigns, :edit, item) do
      save_index_editable(socket, value, change)
    else
      {:noreply, assign_index_editable_result(socket, value, false)}
    end
  end

  defp save_index_editable(socket, value, change) do
    %{assigns: %{item: item, fields: fields, live_resource: live_resource} = assigns} = socket

    opts = [
      before_save_fun: &live_resource.on_item_updating(socket, &1),
      after_save_fun: fn item ->
        live_resource.on_item_updated(socket, item)

        {:ok, item}
      end
    ]

    result = Backpex.Resource.update(item, change, fields, assigns, live_resource, opts)

    valid =
      case result do
        {:ok, _item} -> true
        _error -> false
      end

    {:noreply, assign_index_editable_result(socket, value, valid)}
  end

  defp assign_index_editable_result(socket, value, valid) do
    socket
    |> assign(:valid, valid)
    |> assign(:form, Phoenix.Component.to_form(%{"value" => value}, as: :index_form))
  end
end
