defmodule Backpex.Filter do
  @moduledoc """
  The base behaviour for all filters. Injects also basic layout, form and delete button for a filters rendering.

  ## Validation

  Filters support changeset-based validation to ensure that URL parameters are validated
  before being applied to queries. Each filter module can implement the `changeset/3` callback
  to apply custom validations, or rely on the default implementation which uses `type/1`.

  ## Conditions

  A filter doesn't query the items itself. Its `c:condition/3` callback returns an expression of the items the filter
  keeps, and the adapter of the LiveResource turns it into a query. Write the expression with `Backpex.Expr.expr/1`,
  which `use Backpex.Filter` imports:

      def condition(field, value, _assigns), do: expr(ref(^field) >= ^value)

  `ref(^field)` refers to the field the filter is configured for. An expression may also refer to other fields, to
  fields of related items with a path such as `author.name`, and to related items with `exists/2`, e.g. to keep the
  posts with one of the selected tags:

      def condition(_field, tag_ids, _assigns), do: expr(exists(tags, id in ^tag_ids))

  The adapter casts each value to the type of the field. `Backpex.Adapters.Ecto` also compares an integer field with an
  integer beyond the range of the column, e.g. `expr(likes < 3_000_000_000)` on an `integer` column keeps every item
  with likes. See `Backpex.Expr` for all operators and functions, and for
  expressions that only one adapter understands, such as a fragment of SQL.

  A filter can't change the query itself, e.g. join a table or select distinct items, as the adapter decides how to
  join, order and paginate the items.

  ## Implementing a Custom Filter

  When implementing a custom filter, you should:

  1. Implement `type/1` to return the Ecto type for your filter's value
  2. Optionally implement `changeset/3` for custom validations
  3. Implement `condition/3` which receives the already-validated and casted values

  ## Example

      defmodule MyFilter do
        use Backpex.Filter

        @impl Backpex.Filter
        def type(_assigns), do: :integer

        @impl Backpex.Filter
        def changeset(changeset, field, _assigns) do
          changeset
          |> Ecto.Changeset.validate_number(field, greater_than: 0)
        end

        @impl Backpex.Filter
        def condition(field, value, _assigns), do: expr(ref(^field) >= ^value)
      end

  """

  alias Phoenix.LiveView.Rendered
  alias Phoenix.LiveView.Socket

  @typedoc """
  The expression of the items a filter keeps, see the [Conditions](#module-conditions) section. A keyword list stands
  for fields that equal values, see `Backpex.Expr`.
  """
  @type condition :: Backpex.Expr.t() | keyword()

  @doc """
  Defines whether the filter can be used or not.
  """
  @callback can?(Socket.assigns()) :: boolean()

  @doc """
  If no label is defined on the filter map, this value is used as the filter label.
  """
  @callback label :: String.t()

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

      def type(_assigns), do: :string
      def type(_assigns), do: {:array, :string}
      def type(_assigns), do: :map

  """
  @callback type(assigns :: map()) :: atom() | tuple()

  @doc """
  Applies validation to the changeset for this filter's field.

  Called during changeset building. The default implementation simply returns
  the changeset unchanged (relying on type casting). Override this to add
  custom validations.

  ## Parameters

    * `changeset` - The Ecto changeset being built
    * `field` - The atom key for this filter
    * `assigns` - Socket assigns for context

  ## Examples

      def changeset(changeset, field, _assigns) do
        changeset
        |> Ecto.Changeset.validate_inclusion(field, ["active", "inactive"])
      end

  """
  @callback changeset(Ecto.Changeset.t(), atom(), assigns :: map()) :: Ecto.Changeset.t()

  @doc """
  Public validation API for testing and programmatic validation.

  Returns `{:ok, casted_value}` on success or `{:error, errors}` on failure.
  The default implementation builds a mini-changeset and validates it.

  ## Parameters

    * `value` - The raw value to validate
    * `assigns` - Socket assigns for context

  ## Examples

      iex> MyFilter.validate("active", %{})
      {:ok, "active"}

      iex> MyFilter.validate("invalid", %{})
      {:error, [value: {"is invalid", []}]}

  """
  @callback validate(value :: any(), assigns :: map()) :: {:ok, any()} | {:error, keyword()}

  @doc """
  Returns the expression of the items the filter keeps, see the [Conditions](#module-conditions) section, or `nil` to
  keep all items.

  The `value` parameter contains the already-validated and casted value from the changeset.
  """
  @callback condition(field :: atom(), value :: any(), assigns :: map()) :: condition() | nil

  @doc """
  Renders the filters selected value(s).
  """
  @callback render(Socket.assigns()) :: Rendered.t()

  @doc """
  Renders the filters options form.
  """
  @callback render_form(Socket.assigns()) :: Rendered.t()

  @optional_callbacks label: 0

  defmacro __using__(_opts) do
    quote do
      @behaviour Backpex.Filter

      import Backpex.Expr, only: [expr: 1]
      import Ecto.Changeset

      @impl Backpex.Filter
      def can?(_assigns), do: true

      @impl Backpex.Filter
      def type(_assigns), do: :string

      @impl Backpex.Filter
      def changeset(changeset, _field, _assigns), do: changeset

      @impl Backpex.Filter
      def validate(value, assigns) do
        type = type(assigns)
        changeset = {%{}, %{value: type}} |> cast(%{value: value}, [:value])
        changeset = changeset(changeset, :value, assigns)

        case apply_action(changeset, :validate) do
          {:ok, data} -> {:ok, Map.get(data, :value)}
          {:error, changeset} -> {:error, changeset.errors}
        end
      end

      @impl Backpex.Filter
      def condition(_field, _value, _assigns) do
        raise """
        You must implement the condition/3 callback in your filter module. Filters no longer build queries with
        query/4, see the guide on upgrading to v0.24.

        Example:

            @impl Backpex.Filter
            def condition(field, value, _assigns), do: expr(ref(^field) == ^value)
        """
      end

      defoverridable can?: 1, type: 1, changeset: 3, validate: 2, condition: 3

      @before_compile Backpex.Filter
    end
  end

  # Backpex no longer calls `query/4`, so a filter that still defines it would raise when it is applied, or silently
  # apply the default condition of a built-in filter.
  defmacro __before_compile__(env) do
    if Module.defines?(env.module, {:query, 4}, :def) do
      raise CompileError,
        file: env.file,
        description: """
        #{inspect(env.module)} defines query/4, but filters no longer build queries. Return an expression from \
        condition/3 instead, see the guide on upgrading to v0.24.
        """
    end
  end
end
