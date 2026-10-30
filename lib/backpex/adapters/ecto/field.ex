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
  Returns the schema of the column the field shows. Receives the field and the schema of the resource.

  Without it, the adapter uses the schema of the association for association fields (see
  `c:Backpex.Field.association?/1`) and the schema of the resource for any other field.
  """
  @callback schema(field :: tuple(), schema :: module()) :: module()

  @doc """
  Returns the condition that compares the field to the search string, wrapped into `Ecto.Query.dynamic/2`.

  Receives the name of the binding of the schema of the field (see `c:schema/2`), the name of the column and the search
  string, which starts and ends with `%`. Without it, the adapter compares the column to the search string with `ilike`,
  and casts columns that are not strings to text first.
  """
  @callback search_condition(schema_name :: atom(), field_name :: atom(), search_string :: String.t()) ::
              Ecto.Query.dynamic_expr()

  @optional_callbacks schema: 2, search_condition: 3
end
