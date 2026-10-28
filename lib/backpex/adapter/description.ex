defmodule Backpex.Adapter.Description do
  @moduledoc """
  The description of the items of a resource, or of related items, that an adapter returns from
  `c:Backpex.Adapter.describe/2`.

    * `:primary_key` - the names of the fields of the primary key.
    * `:fields` - a map of field names to maps with:
      * `:type` - the type to cast values to, an `Ecto.Type` such as `:string`, `:integer`, `{:array, :string}` or a
        parameterized type such as `Ecto.Enum`. An adapter for another data source maps its types to Ecto types.
      * `:primitive` - the primitive type behind `:type`, e.g. `:string` for an `Ecto.Enum` of strings.
    * `:relationships` - a map of relationship names to maps with:
      * `:field` - the name of the relationship.
      * `:cardinality` - `:one` or `:many`.
      * `:owner_key` - the field of the items the relationship is based on, e.g. `:user_id` for a `belongs_to :user`
        association.
      * `:through` - for a relationship through other relationships, the relationships it goes through, in order, as
        maps with the same keys. An empty list for any other relationship.

  Backpex uses the description to check and cast the values of expressions (see `Backpex.Expr`), to find the key of a
  relationship and to tell integer fields from others.
  """

  defstruct primary_key: [], fields: %{}, relationships: %{}

  @type field :: %{type: term(), primitive: atom()}

  @type relationship :: %{
          field: atom(),
          cardinality: :one | :many,
          owner_key: atom() | nil,
          through: [relationship()]
        }

  @type t :: %__MODULE__{
          primary_key: [atom()],
          fields: %{atom() => field()},
          relationships: %{atom() => relationship()}
        }
end
