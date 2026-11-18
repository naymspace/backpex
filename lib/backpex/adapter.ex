defmodule Backpex.Adapter do
  @moduledoc ~S"""
  Specification of the datalayer adapter.

  Backpex is Ecto-first: `Backpex.Adapters.Ecto` is the default adapter. Outside of adapters, Backpex builds no queries,
  calls no repo and doesn't inspect schemas. LiveResources read and write data only through the callbacks of this
  behaviour, mostly via `Backpex.Resource`. Forms are built from `Ecto.Changeset`s for every data source, see
  `c:change/6`.

  Backpex builds a `Backpex.Query` for every read, and the adapter runs it with `c:read/1`, `c:count/1` and
  `c:aggregate/1`. Filters return expressions (see `Backpex.Expr`) and metrics name an aggregate (see
  `Backpex.Metric`), which end up in the query. Adapters don't get the fields or filters of the LiveResource, so an
  adapter for another data source only has to run queries.

  Options that only one adapter understands belong to it, e.g. the `:options_query` of association fields belongs to
  `Backpex.Adapters.Ecto`. An adapter adds options to fields with `c:field_config_schema/0`.

  ## `use Backpex.Adapter`

  When you `use Backpex.Adapter`, it declares this behaviour and accepts these options:

    * `:config_schema` - the `NimbleOptions` schema of the `adapter_config` option of a LiveResource.
    * `:field_config_schema` - the `NimbleOptions` schema of the options the adapter adds to fields, returned by
      `c:field_config_schema/0`.
    * `:supports` - the parts of a `Backpex.Query` the adapter runs itself, see `c:supports?/2`: `:all`, or a list of
      features such as `[:filter, :sort]`. Required. `supports: []` is right for an adapter that only returns all
      items from `c:read/1`, as Backpex then applies every part of a query to the items in memory. There is no default,
      because an adapter that says it runs a part and doesn't would return the items of other filters, scopes or pages.

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
      @supports Backpex.Adapter.fetch_supports!(opts, __MODULE__)

      @behaviour Backpex.Adapter

      @impl Backpex.Adapter
      def validate_config!(config) do
        NimbleOptions.validate!(config, @config_schema)
      end

      @impl Backpex.Adapter
      def field_config_schema, do: @field_config_schema

      @impl Backpex.Adapter
      def supports?(_live_resource, feature), do: Backpex.Adapter.supported?(@supports, feature)

      defoverridable field_config_schema: 0, supports?: 2
    end
  end

  @doc """
  Validates the `:adapter_config` of a LiveResource and returns it, or raises if it is invalid.

  `use Backpex.LiveResource` calls it at compile time. `use Backpex.Adapter` defines it and validates the configuration
  against the `:config_schema` option.
  """
  @callback validate_config!(config :: keyword()) :: keyword()

  @doc """
  Returns the `NimbleOptions` schema of the options the adapter adds to every field, e.g. `[tenant: [type: :atom]]`.
  Backpex validates the options of fields against it, together with the options of the field. `Backpex.Adapters.Ecto`
  adds none.
  """
  @callback field_config_schema() :: keyword()

  @doc """
  Returns whether the adapter runs the `feature` of a `Backpex.Query` itself. Backpex applies the parts of a query the
  adapter doesn't run to the items in memory, see `Backpex.Query.apply_to/2`. So an adapter that runs no part of a query
  only returns all items from `c:read/1`.

  The features are:

    * `:filter` - the `:filter` of a query. Backpex also asks for `{:filter, operator}` with the operators of the
      expression, e.g. `{:filter, :contains}` or `{:filter, :exists}`, see `Backpex.Expr`. An aggregate of related
      items in a filter (see `Backpex.Expr.aggregate/3`) is the operator `{:filter, :aggregate}`, next to the operators
      of its `:value` and its `:where`.
    * `:search`, `:sort`, `:offset` and `:limit` - these parts of a query.
    * `:computed` - the `:computed` values of a query. Backpex computes them before every other part.
    * `:count` and `:aggregate` - `c:count/1` and `c:aggregate/1`.
    * `:insert`, `:update` and `:delete` - writing items with `c:insert/2`, `c:update/2` and `c:update_all/3`, and
      `c:delete_all/2`. Without them, `Backpex.Authorization` denies the `:new`, `:edit` and `:delete` actions, so the
      views hide them. Backpex can't apply writes in memory.

  The `:load` of a query is no feature: every adapter with relationships loads them into the items, see `c:read/1`.

  Parts depend on the ones before them, in the order computed, filter, search, sort, offset and limit. If the adapter doesn't
  run a part, Backpex applies it and every part after it in memory, e.g. the sort of a query whose filter the adapter
  doesn't run. Then the adapter gets the query without these parts.

  `use Backpex.Adapter` defines it from its `:supports` option: `:all` or a list of features. `:filter` stands for all
  operators. A list of `{:filter, operator}` instead lets the adapter run the filters that only use these operators,
  e.g. `[{:filter, :==}, {:filter, :in}, :sort]`.

  Backpex treats an adapter module that doesn't define it as one that runs no part of a query.
  """
  @callback supports?(live_resource :: module(), feature :: atom() | {atom(), atom()}) :: boolean()

  @doc false
  def fetch_supports!(opts, adapter) do
    case Keyword.fetch(opts, :supports) do
      {:ok, :all} ->
        :all

      {:ok, features} when is_list(features) ->
        features

      {:ok, other} ->
        raise ArgumentError,
              "expected the :supports option of `use Backpex.Adapter` in #{inspect(adapter)} to be :all or a list of " <>
                "features, got: #{inspect(other)}"

      :error ->
        raise ArgumentError, """
        #{inspect(adapter)} has to pass the :supports option to `use Backpex.Adapter`: the parts of a query the adapter \
        runs itself, see Backpex.Adapter.supports?/2.

        Pass `supports: :all` if the adapter runs every part of a query (filter, search, sort, offset, limit, count and \
        aggregate), or `supports: []` if it only returns all items, so Backpex applies the query to them in memory.
        """
    end
  end

  @doc false
  def supported?(:all, _feature), do: true

  def supported?(features, :filter) when is_list(features),
    do: :filter in features or Enum.any?(features, &match?({:filter, _operator}, &1))

  def supported?(features, {:filter, _operator} = feature) when is_list(features),
    do: :filter in features or feature in features

  def supported?(features, feature) when is_list(features), do: feature in features

  @doc """
  Puts the options of fields that only the adapter understands into the query: the ones it adds (see
  `c:field_config_schema/0`), or e.g. the `:options_query` of association fields, which `Backpex.Adapters.Ecto` takes.
  Keep the data for later in the `:native` field of the query, see `Backpex.Query.put_native/3`.

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

  The adapter only gets the parts it supports, see `c:supports?/2`. It always gets the `:load`: the relationships of
  association fields and the ones the parts Backpex applies in memory read, e.g. the `author` of the filter
  `author.name == "Ann"`. A loaded relationship is the related item, a list of related items or `nil` under the name of
  the relationship in the item. Backpex raises if it has to read a relationship in memory that is missing in an item.

  Backpex calls it only with valid queries, so an item that doesn't exist results in an empty list.
  """
  @callback read(query :: Backpex.Query.t()) :: {:ok, list()} | {:error, term()}

  @doc """
  Returns the number of items the query matches. Backpex removes the sorts, the limit and the offset before, see
  `Backpex.Query.unset/2`. The `:load` stays, as the search and the filters may refer to computed values of related
  items (see `Backpex.Query.computed_expr/2`), but the adapter doesn't need to load the relationships.

  Optional: without it, or if `c:supports?/2` doesn't support `:count`, Backpex counts the items of `c:read/1`.
  """
  @callback count(query :: Backpex.Query.t()) :: {:ok, non_neg_integer()} | {:error, term()}

  @doc """
  Returns a map of the names of the `:aggregates` of the query to their values, e.g. the data of metrics. Each aggregate
  covers the items the query matches that also match its `:where` expression. Backpex removes the sorts, the limit and
  the offset before, and keeps the `:load` as for `c:count/1`.

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
  Inserts the item of the changeset of `c:change/6`. Returns the inserted item, or the changeset with errors, e.g. of
  constraints of the data source.
  """
  @callback insert(changeset :: Ecto.Changeset.t(), live_resource :: module()) ::
              {:ok, struct()} | {:error, Ecto.Changeset.t() | term()}

  @doc """
  Updates the item of the changeset of `c:change/6`. Returns the updated item, or the changeset with errors.
  """
  @callback update(changeset :: Ecto.Changeset.t(), live_resource :: module()) ::
              {:ok, struct()} | {:error, Ecto.Changeset.t() | term()}

  @doc """
  Sets the fields of `changes` to their values in every item, e.g. `%{deleted_at: now}` for a soft delete. Returns the
  number of updated items. Backpex checked the fields against `c:describe/2` and cast the values to their types.
  """
  @callback update_all(items :: list(struct()), changes :: %{atom() => term()}, live_resource :: module()) ::
              {:ok, non_neg_integer()} | {:error, term()}

  @doc """
  Returns the changeset of the form of an item: `attrs` cast onto the item by the changeset function of the
  LiveResource for the action, after `c:Backpex.Field.before_changeset/5` of every field. The form of every view is
  built from it, and `c:insert/2` and `c:update/2` write it.

  An `Ecto.Changeset` is the form type of Backpex for every data source, as it doesn't need a database: changesets
  work with `Ecto.Schema` and embedded schemas, and with schemaless types from `c:describe/2`.
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

  @optional_callbacks field_config_schema: 0, put_field_options: 2, count: 1, aggregate: 1
end
