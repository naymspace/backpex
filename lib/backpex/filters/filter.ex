defmodule Backpex.Filter do
  @config_schema [
    module: [
      doc: "The filter module.",
      type: :atom,
      required: true
    ],
    label: [
      doc: "The filter label. Required unless the filter module implements `c:label/0`.",
      type: :string
    ],
    default: [
      doc: """
      The value of the filter when the index view is opened without filters. Also see the
      [default values](/guides/filter/how-to-add-a-filter.md#default-values) section.
      """,
      type: :any
    ],
    presets: [
      doc: """
      A list of maps with a `:label` and a `:values` function that returns the value of the filter. See the
      [filter presets](/guides/filter/filter-presets.md) guide.
      """,
      type: {:list, :map}
    ],
    can?: [
      doc: """
      Function to change the visibility of the filter. Receives the assigns and has to return a boolean. The filter is
      only shown if this function and `c:can?/1` of the filter module return `true`.
      """,
      type: {:fun, 1}
    ],
    condition: [
      doc: """
      Function that returns the expression of the items the filter keeps, instead of `c:condition/3` of the filter
      module. Receives the same arguments as `c:condition/3`. See the [Conditions](#module-conditions) section.
      """,
      type: {:fun, 3}
    ]
  ]

  @moduledoc """
  The base behaviour for all filters. Injects also basic layout, form and delete button for a filters rendering.

  ## Configuration

  A LiveResource lists its filters in `c:Backpex.LiveResource.filters/0`, like its fields. Each filter is configured
  with a map that names the filter module and its options. The name of the filter is the field it filters by.

      def filters do
        [
          status: %{
            module: Backpex.Filters.Select,
            label: "Status",
            options: [{"Open", "open"}, {"Closed", "closed"}]
          },
          likes: %{
            module: Backpex.Filters.Range,
            label: "Likes",
            type: :number
          }
        ]
      end

  Backpex ships with the generic filters `Backpex.Filters.Boolean`, `Backpex.Filters.MultiSelect`,
  `Backpex.Filters.Range` and `Backpex.Filters.Select`. Their options are described in their modules.

  ### Options

  These are general filter options which can be used on every filter. Check the filter modules for filter-specific
  options.

  #{NimbleOptions.docs(@config_schema)}

  ## Callbacks

  The callbacks of a filter receive the filter as a `{name, config}` tuple, where `config` is the validated map of
  options from the LiveResource. `c:render/1` and `c:render_form/1` find this tuple in `@filter`.

  ## Validation

  Filters support changeset-based validation to ensure that URL parameters are validated
  before being applied to queries. Each filter module can implement the `changeset/3` callback
  to apply custom validations, or rely on the default implementation which uses `type/2`.

  ## Conditions

  A filter doesn't query the items itself. Its `c:condition/3` callback returns an expression of the items the filter
  keeps, and the adapter of the LiveResource turns it into a query. Write the expression with `Backpex.Expr.expr/1`,
  which `use Backpex.Filter` imports:

      def condition({field, _config}, value, _assigns), do: expr(ref(^field) >= ^value)

  `ref(^field)` refers to the field the filter is configured for. An expression may also refer to other fields, to
  fields of related items with a path such as `author.name`, and to related items with `exists/2`, e.g. to keep the
  posts with one of the selected tags:

      def condition(_filter, tag_ids, _assigns), do: expr(exists(tags, id in ^tag_ids))

  The adapter casts each value to the type of the field. See `Backpex.Expr` for all operators and functions, and for
  expressions that only one adapter understands, such as a fragment of SQL.

  A filter can't change the query itself, e.g. join a table or select distinct items, as the adapter decides how to
  join, order and paginate the items.

  To change the expression of a single filter, pass a function to the `:condition` option instead of implementing a
  filter module. Import `Backpex.Expr` in the LiveResource to use `expr/1` there:

      deleted_at: %{
        module: Backpex.Filters.Select,
        label: "Status",
        options: [{"Active", "active"}, {"Deleted", "deleted"}],
        condition: fn
          {field, _config}, "active", _assigns -> expr(is_nil(ref(^field)))
          {field, _config}, "deleted", _assigns -> expr(not is_nil(ref(^field)))
        end
      }

  ## Implementing a Custom Filter

  When implementing a custom filter, you should:

  1. Implement `type/2` to return the Ecto type for your filter's value
  2. Optionally implement `changeset/3` for custom validations
  3. Implement `condition/3` which receives the already-validated and casted values
  4. Implement `render/1` and `render_form/1`
  5. Optionally pass a `:config_schema` to `use Backpex.Filter` to define the options of your filter

  ## Example

      defmodule MyFilter do
        use BackpexWeb, :filter
        use Backpex.Filter,
          config_schema: [
            min: [doc: "The smallest value.", type: :integer, default: 0]
          ]

        @impl Backpex.Filter
        def type(_filter, _assigns), do: :integer

        @impl Backpex.Filter
        def changeset(changeset, {field, config}, _assigns) do
          Ecto.Changeset.validate_number(changeset, field, greater_than_or_equal_to: config.min)
        end

        @impl Backpex.Filter
        def condition({field, _config}, value, _assigns), do: expr(ref(^field) >= ^value)

        @impl Backpex.Filter
        def render(assigns), do: ~H"{@value}"

        @impl Backpex.Filter
        def render_form(assigns) do
          ~H\"""
          <input type="number" class="input input-sm mt-2 w-full" name={@form[@field].name} value={@value} />
          \"""
        end
      end

  """

  alias Phoenix.LiveView.Rendered
  alias Phoenix.LiveView.Socket

  @typedoc """
  The expression of the items a filter keeps, see the [Conditions](#module-conditions) section. A keyword list stands
  for fields that equal values, see `Backpex.Expr`.
  """
  @type condition :: Backpex.Expr.t() | keyword()

  @typedoc """
  A filter: its name and the validated map of its options from the LiveResource.
  """
  @type t :: {atom(), map()}

  @doc """
  Defines whether the filter can be used or not.
  """
  @callback can?(Socket.assigns()) :: boolean()

  @doc """
  If no label is defined on the filter map, this value is used as the filter label.
  """
  @callback label :: String.t()

  @doc """
  Returns the `NimbleOptions` schema of the options of the filter, which `use Backpex.Filter` takes as the
  `:config_schema` option.
  """
  @callback config_schema() :: keyword()

  @doc """
  Returns the Ecto type for this filter's value.

  Used to build schemaless changesets for validation. Common types include:
  - `:string` - for single value select filters
  - `{:array, :string}` - for multi-select or boolean filters
  - `:map` - for range filters with start/end values

  A value from the URL or from persisted filters that cannot be cast to this type is neither applied nor passed to
  `c:render_form/1`, so `c:render_form/1` only receives values of this type. If the type allows values that
  `c:render_form/1` cannot render, e.g. a nested map in a `:map`, reject them in `c:changeset/3` with an error that
  has the `validation: :cast` option, as `Backpex.Filters.Range` does.

  ## Examples

      def type(_filter, _assigns), do: :string
      def type(_filter, _assigns), do: {:array, :string}
      def type(_filter, _assigns), do: :map

  """
  @callback type(filter :: t(), assigns :: map()) :: atom() | tuple()

  @doc """
  Applies validation to the changeset for this filter's field.

  Called during changeset building. The default implementation simply returns
  the changeset unchanged (relying on type casting). Override this to add
  custom validations.

  ## Parameters

    * `changeset` - The Ecto changeset being built
    * `filter` - The filter, its name is the key of its value in the changeset
    * `assigns` - Socket assigns for context

  ## Examples

      def changeset(changeset, {field, _config}, _assigns) do
        changeset
        |> Ecto.Changeset.validate_inclusion(field, ["active", "inactive"])
      end

  """
  @callback changeset(Ecto.Changeset.t(), filter :: t(), assigns :: map()) :: Ecto.Changeset.t()

  @doc """
  Public validation API for testing and programmatic validation.

  Returns `{:ok, casted_value}` on success or `{:error, errors}` on failure.
  The default implementation builds a mini-changeset and validates it.

  ## Parameters

    * `filter` - The filter
    * `value` - The raw value to validate
    * `assigns` - Socket assigns for context

  ## Examples

      iex> MyFilter.validate({:status, %{module: MyFilter}}, "active", %{})
      {:ok, "active"}

      iex> MyFilter.validate({:status, %{module: MyFilter}}, "invalid", %{})
      {:error, [value: {"is invalid", []}]}

  """
  @callback validate(filter :: t(), value :: any(), assigns :: map()) :: {:ok, any()} | {:error, keyword()}

  @doc """
  Returns the expression of the items the filter keeps, see the [Conditions](#module-conditions) section, or `nil` to
  keep all items.

  The `value` parameter contains the already-validated and casted value from the changeset.
  """
  @callback condition(filter :: t(), value :: any(), assigns :: map()) :: condition() | nil

  @doc """
  Renders the filters selected value(s).
  """
  @callback render(Socket.assigns()) :: Rendered.t()

  @doc """
  Renders the filters options form.
  """
  @callback render_form(Socket.assigns()) :: Rendered.t()

  @optional_callbacks label: 0, config_schema: 0

  @doc """
  Returns the schema of the options every filter takes.
  """
  def default_config_schema, do: @config_schema

  @doc """
  Validates the options of a filter against `default_config_schema/0` and the `c:config_schema/0` of its module.

  Returns the filter with the validated options. Raises if an option is invalid or the filter has no label.
  """
  @spec validate_config!(t(), module()) :: t()
  def validate_config!({name, config} = _filter, live_resource) do
    module = Map.get(config, :module)
    schema = @config_schema ++ module_config_schema(module)
    options = Keyword.new(config)

    case NimbleOptions.validate(options, schema) do
      {:ok, validated} ->
        validated = Map.new(validated)

        if not Map.has_key?(validated, :label) and not function_exported?(module, :label, 0) do
          raise_config_error(name, live_resource, "required :label option not found")
        end

        {name, validated}

      {:error, error} ->
        raise_config_error(name, live_resource, error.message)
    end
  end

  defp module_config_schema(module) when is_atom(module) and not is_nil(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, :config_schema, 0),
      do: module.config_schema(),
      else: []
  end

  defp module_config_schema(_module), do: []

  defp raise_config_error(name, live_resource, message) do
    raise ArgumentError, """
    Configuration error for filter "#{name}" in "#{inspect(live_resource)}".

    #{message}
    """
  end

  @doc """
  Returns the label of a filter: its `:label` option or the `c:label/0` of its module.
  """
  @spec label(t()) :: String.t()
  def label({_name, %{label: label}}), do: label
  def label({_name, %{module: module}}), do: module.label()

  @doc """
  Returns whether a filter can be used: its `:can?` option, if given, and the `c:can?/1` of its module must return
  `true`.
  """
  @spec can?(t(), map()) :: boolean()
  def can?({_name, config}, assigns) do
    can? = Map.get(config, :can?, fn _assigns -> true end)

    can?.(assigns) and config.module.can?(assigns)
  end

  @doc """
  Returns the expression of a filter for a validated value: the result of its `:condition` option, if given, or of the
  `c:condition/3` of its module. Adapters call this function to apply filters.
  """
  @spec to_condition(t(), any(), map()) :: condition() | nil
  def to_condition({_name, %{condition: condition}} = filter, value, assigns), do: condition.(filter, value, assigns)
  def to_condition({_name, %{module: module}} = filter, value, assigns), do: module.condition(filter, value, assigns)

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @behaviour Backpex.Filter

      import Backpex.Expr, only: [expr: 1]
      import Ecto.Changeset

      @filter_config_schema opts[:config_schema] || []

      @impl Backpex.Filter
      def config_schema, do: @filter_config_schema

      @impl Backpex.Filter
      def can?(_assigns), do: true

      @impl Backpex.Filter
      def type(_filter, _assigns), do: :string

      @impl Backpex.Filter
      def changeset(changeset, _filter, _assigns), do: changeset

      @impl Backpex.Filter
      def validate({_name, config} = _filter, value, assigns) do
        filter = {:value, config}
        changeset = {%{}, %{value: type(filter, assigns)}} |> cast(%{value: value}, [:value])
        changeset = changeset(changeset, filter, assigns)

        case apply_action(changeset, :validate) do
          {:ok, data} -> {:ok, Map.get(data, :value)}
          {:error, changeset} -> {:error, changeset.errors}
        end
      end

      @impl Backpex.Filter
      def condition(_filter, _value, _assigns) do
        raise """
        You must implement the condition/3 callback in your filter module or pass the :condition option to the \
        filter. Filters no longer build queries with query/4, see the guide on upgrading to v0.24.

        Example:

            @impl Backpex.Filter
            def condition({field, _config}, value, _assigns), do: expr(ref(^field) == ^value)
        """
      end

      defoverridable config_schema: 0, can?: 1, type: 2, changeset: 3, validate: 3, condition: 3

      @before_compile Backpex.Filter
    end
  end

  # Backpex no longer calls these functions, so a filter that still defines them would raise when it is applied, or
  # silently fall back to the default implementation.
  @removed_callbacks [
    {{:query, 4}, "filters no longer build queries. Return an expression from condition/3 instead"},
    {{:type, 1}, "type/2 now receives the filter. Implement type/2 instead"},
    {{:validate, 2}, "validate/3 now receives the filter. Implement validate/3 instead"}
  ]

  defmacro __before_compile__(env) do
    for {{name, arity}, hint} <- @removed_callbacks, Module.defines?(env.module, {name, arity}, :def) do
      raise CompileError,
        file: env.file,
        description:
          "#{inspect(env.module)} defines #{name}/#{arity}, but #{hint}, see the guide on upgrading to v0.24."
    end

    :ok
  end
end
