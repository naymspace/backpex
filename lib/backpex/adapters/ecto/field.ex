defmodule Backpex.Adapters.Ecto.Field do
  @moduledoc """
  The Ecto-specific callbacks of fields. Only `Backpex.Adapters.Ecto` calls them.

      defmodule MyAppWeb.Fields.Code do
        use Backpex.Field

        @behaviour Backpex.Adapters.Ecto.Field

        import Ecto.Query

        @impl Backpex.Adapters.Ecto.Field
        def search_condition(schema_name, field_name, search_string) do
          dynamic(
            [{^schema_name, schema_name}],
            ilike(field(schema_name, ^field_name), ^String.trim_leading(search_string, "%"))
          )
        end

        # ...the callbacks of `Backpex.Field`
      end
  """

  @doc """
  Returns the condition that compares the field to the search string, wrapped into `Ecto.Query.dynamic/2`.

  Receives the name of the binding of the column: the join of the association for an association field (see
  `c:Backpex.Field.association?/1`), e.g. `:backpex_author`, or the binding of the schema of the resource, e.g. `:post`.
  Then the name of the column (the `:display_field` of the field, or its name) and the search string, which starts and
  ends with `%`. Without it, the adapter compares the column to the search string with `ilike`,
  and casts columns that are not strings to text first.
  """
  @callback search_condition(schema_name :: atom(), field_name :: atom(), search_string :: String.t()) ::
              Ecto.Query.dynamic_expr()

  @optional_callbacks search_condition: 3
end
