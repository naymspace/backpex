defmodule Backpex.Adapter do
  @moduledoc ~S"""
  Specification of the datalayer adapter.

  Backpex is Ecto-first: `Backpex.Adapters.Ecto` is the default adapter. Outside of adapters, Backpex builds no queries,
  calls no repo and doesn't inspect schemas. LiveResources read and write data only through the callbacks of this
  behaviour, mostly via `Backpex.Resource`. Forms still use changesets.

  Backpex builds a `Backpex.Query` for every read, and the adapter runs it with `c:read/1`, `c:count/1` and
  `c:aggregate/1`. Filters return expressions (see `Backpex.Expr`) and metrics name an aggregate (see
  `Backpex.Metric`), which end up in the query. Adapters don't get the fields or filters of the LiveResource, so an
  adapter for another data source only has to run queries.

  Options and callbacks that only one adapter understands belong to it, e.g. the `:select` option of fields and
  `Backpex.Adapters.Ecto.Field` belong to `Backpex.Adapters.Ecto`. An adapter adds options to fields with
  `c:field_config_schema/0`.

  ## `use Backpex.Adapter`

  When you `use Backpex.Adapter`, it declares this behaviour and accepts these options:

    * `:config_schema` - the `NimbleOptions` schema of the `adapter_config` option of a LiveResource.
    * `:field_config_schema` - the `NimbleOptions` schema of the options the adapter adds to fields, returned by
      `c:field_config_schema/0`.
    * `:supports` - the parts of a `Backpex.Query` the adapter runs itself, see `c:supports?/2`. Defaults to `:all`.

  > ### Work in progress {: .warning}
  >
  > The `Backpex.Adapter` behaviour is still under development and may change in future updates. Keep this in mind when
  > building a new adapter.

  ## Community Adapters

  - **Ash**: Ash support for Backpex is maintained as a separate community project: [ash_backpex](https://github.com/enoonan/ash_backpex)
  """

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @config_schema opts[:config_schema] || []
      @field_config_schema opts[:field_config_schema] || []
      @supports Keyword.get(opts, :supports, :all)

      @behaviour Backpex.Adapter

      def validate_config!(config) do
        NimbleOptions.validate!(config, @config_schema)
      end

      def field_config_schema, do: @field_config_schema

      def supports?(_live_resource, feature), do: Backpex.Adapter.supported?(@supports, feature)

      defoverridable field_config_schema: 0, supports?: 2
    end
  end

  @doc """
  Returns the `NimbleOptions` schema of the options the adapter adds to every field, e.g. `:select` of
  `Backpex.Adapters.Ecto`. Backpex validates the options of fields against it, together with the options of the field.
  """
  @callback field_config_schema() :: keyword()

  @doc """
  Returns whether the adapter runs the `feature` of a `Backpex.Query` itself. Backpex applies the parts of a query the
  adapter doesn't run to the items in memory, see `Backpex.Query.apply_to/2`. So an adapter that runs no part of a query
  only returns all items from `c:read/1`.

  The features are:

    * `:filter` - the `:filter` of a query. Backpex also asks for `{:filter, operator}` with the operators of the
      expression, e.g. `{:filter, :contains}` or `{:filter, :exists}`, see `Backpex.Expr`.
    * `:search`, `:sort`, `:offset` and `:limit` - these parts of a query.
    * `:load` - the relationships of the `:load` of a query.
    * `:count` and `:aggregate` - `c:count/1` and `c:aggregate/1`.

  Parts depend on the ones before them, in the order filter, search, sort, offset and limit. If the adapter doesn't
  run a part, Backpex applies it and every part after it in memory, e.g. the sort of a query whose filter the adapter
  doesn't run. Then the adapter gets the query without these parts.

  `use Backpex.Adapter` defines it from its `:supports` option: `:all` or a list of features. `:filter` stands for all
  operators. A list of `{:filter, operator}` instead lets the adapter run the filters that only use these operators,
  e.g. `[{:filter, :==}, {:filter, :in}, :sort]`.
  """
  @callback supports?(live_resource :: module(), feature :: atom() | {atom(), atom()}) :: boolean()

  @doc false
  def supported?(:all, _feature), do: true

  def supported?(features, :filter) when is_list(features),
    do: :filter in features or Enum.any?(features, &match?({:filter, _operator}, &1))

  def supported?(features, {:filter, _operator} = feature) when is_list(features),
    do: :filter in features or feature in features

  def supported?(features, feature) when is_list(features), do: feature in features

  @doc """
  Puts the options the adapter adds to fields (see `c:field_config_schema/0`) into the query, e.g. the `:select` option
  of `Backpex.Adapters.Ecto` as a computed value. Keep the data for later in the `:native` field of the query, see
  `Backpex.Query.put_native/3`.

  Backpex calls it with every field of the LiveResource when it builds a query of the items of the resource, and with
  an association field when it builds the query of the options of the field. Then the `:from` of the query is the name
  of the field.

  Optional: adapters that add no options to fields don't need it, as `c:read/1`, `c:count/1` and `c:aggregate/1` only
  get the query.
  """
  @callback put_field_options(query :: Backpex.Query.t(), field :: {atom(), map()}) :: Backpex.Query.t()

  @doc """
  Returns the items of the query, see `Backpex.Query`: the items at the end of its `:from`, that match its `:filter`
  and `:search`, sorted by `Backpex.Query.sorts/1`, after its `:offset` and up to its `:limit`, with the relationships
  of its `:load` and the values of its `:computed`.

  Backpex calls it only with valid queries, so an item that doesn't exist results in an empty list.
  """
  @callback read(query :: Backpex.Query.t()) :: {:ok, list()} | {:error, term()}

  @doc """
  Returns the number of items the query matches. Backpex removes the sorts, the limit, the offset and the relationships
  to load before, see `Backpex.Query.unset/2`.

  Optional: without it, or if `c:supports?/2` doesn't support `:count`, Backpex counts the items of `c:read/1`.
  """
  @callback count(query :: Backpex.Query.t()) :: {:ok, non_neg_integer()} | {:error, term()}

  @doc """
  Returns a map of the names of the `:aggregates` of the query to their values, e.g. the data of metrics. Each aggregate
  covers the items the query matches that also match its `:where` expression. Backpex removes the sorts, the limit, the
  offset and the relationships to load before.

  Optional: without it, or if `c:supports?/2` doesn't support `:aggregate`, Backpex computes the aggregates from the
  items of `c:read/1`.
  """
  @callback aggregate(query :: Backpex.Query.t()) :: {:ok, %{atom() => term()}} | {:error, term()}

  @doc """
  Returns a new item that has not been saved yet, e.g. for the form of the `:new` action.
  """
  @callback new_item(assigns :: map(), live_resource :: module()) :: struct()

  @doc """
  Returns the description of the items of the resource: their primary key, fields and relationships, see
  `Backpex.Adapter.Description`. With a `path` of relationships, e.g. `[:author]`, returns the description of the related
  items at its end. Returns `nil` if there is no such path.

  Backpex checks and casts expressions with it (see `Backpex.Expr.cast/2`), finds the key of a relationship for
  association fields and tells integer fields from others, e.g. in `Backpex.Filters.Range`. Use
  `Backpex.Resource.describe/2` to call it.
  """
  @callback describe(path :: [atom()], live_resource :: module()) :: Backpex.Adapter.Description.t() | nil

  @doc """
  Inserts given item.
  """
  @callback insert(item :: struct(), live_resource :: module()) :: {:ok, struct()} | {:error, term()}

  @doc """
  Updates given item.
  """
  @callback update(item :: struct(), live_resource :: module()) :: {:ok, struct()} | {:error, term()}

  @doc """
  Updates given items.
  """
  @callback update_all(items :: list(struct()), updates :: keyword(), live_resource :: module()) ::
              {:ok, non_neg_integer()}

  @doc """
  Applies a change to a given item.
  """
  @callback change(
              item :: struct(),
              attrs :: map(),
              fields :: term(),
              assigns :: list(),
              live_resource :: module(),
              opts :: keyword()
            ) :: Ecto.Changeset.t()

  @doc """
  Puts the associated items `value` into the association `name` of the changeset, e.g. when an item is added to a
  `Backpex.Fields.HasManyThrough` field.
  """
  @callback put_assoc(changeset :: Ecto.Changeset.t(), name :: atom(), value :: term(), live_resource :: module()) ::
              Ecto.Changeset.t()

  @doc """
  Deletes multiple items.

  Returns `{:error, :foreign_key_violation}` if an item can't be deleted because other data still references it.
  """
  @callback delete_all(items :: list(struct()), live_resource :: module()) :: {:ok, term()} | {:error, term()}

  @optional_callbacks field_config_schema: 0, put_field_options: 2, supports?: 2, count: 1, aggregate: 1
end
