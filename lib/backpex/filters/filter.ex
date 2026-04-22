defmodule Backpex.Filter do
  @moduledoc """
  The base behaviour for all filters. Injects also basic layout, form and delete button for a filters rendering.

  ## Validation

  Filters support changeset-based validation to ensure that URL parameters are validated
  before being applied to queries. Each filter module can implement the `changeset/3` callback
  to apply custom validations, or rely on the default implementation which uses `type/1`.

  ## Implementing a Custom Filter

  When implementing a custom filter, you should:

  1. Implement `type/1` to return the Ecto type for your filter's value
  2. Optionally implement `changeset/3` for custom validations
  3. Implement `query/4` which receives the already-validated and casted values

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
        def query(query, field, value, _assigns) do
          Ecto.Query.where(query, [x], field(x, ^field) == ^value)
        end
      end

  """

  @doc """
  Defines whether the filter can be used or not.
  """
  @callback can?(Phoenix.LiveView.Socket.assigns()) :: boolean()

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
  The filter query that is executed if an option was selected.

  The `value` parameter contains the already-validated and casted value from the changeset.
  """
  @callback query(Ecto.Query.t(), any(), any(), assigns :: map()) :: Ecto.Query.t()

  @doc """
  Renders the filters selected value(s).
  """
  @callback render(Phoenix.LiveView.Socket.assigns()) :: Phoenix.LiveView.Rendered.t()

  @doc """
  Renders the filters options form.
  """
  @callback render_form(Phoenix.LiveView.Socket.assigns()) :: Phoenix.LiveView.Rendered.t()

  @optional_callbacks label: 0

  defmacro __using__(_opts) do
    quote do
      @behaviour Backpex.Filter

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
      def query(_query, _attribute, _value, _assigns) do
        raise """
        You must implement the query/4 callback in your filter module.

        Example:

            @impl Backpex.Filter
            def query(query, attribute, value, _assigns) do
              Ecto.Query.where(query, [x], field(x, ^attribute) == ^value)
            end
        """
      end

      defoverridable can?: 1, type: 1, changeset: 3, validate: 2, query: 4
    end
  end
end
