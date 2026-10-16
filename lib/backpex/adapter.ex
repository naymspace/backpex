defmodule Backpex.Adapter do
  @moduledoc ~S"""
  Specification of the datalayer adapter.

  Backpex is Ecto-first: `Backpex.Adapters.Ecto` is the default adapter. Outside of adapters, Backpex builds no queries,
  calls no repo and doesn't inspect schemas. LiveResources read and write data only through the callbacks of this
  behaviour, mostly via `Backpex.Resource`. Forms still use changesets.

  Options and callbacks that take Ecto queries belong to `Backpex.Adapters.Ecto`, and only that adapter calls them: the
  `:select` option of fields, the `:options_query` option of association fields, `c:Backpex.Field.search_condition/3`,
  `c:Backpex.Field.before_changeset/6`, `c:Backpex.Filter.query/4` and `c:Backpex.Metric.query/3`.

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

      @behaviour Backpex.Adapter

      def validate_config!(config) do
        NimbleOptions.validate!(config, @config_schema)
      end
    end
  end

  @doc """
  Gets a database record with the given primary key value.

  Should return `nil` if no result was found.
  """
  @callback get(primary_value :: term(), fields :: list(), assigns :: map(), live_resource :: module()) ::
              {:ok, struct() | nil} | {:error, term()}

  @doc """
  Returns a list of items by given criteria.

  The criteria may contain:

    * `:search` - a tuple of the search string and the searchable fields.
    * `:filter_values` and `:filter_configs` - the validated values and the configurations of the active filters.
    * `:order` - a map with the keys `:by` (the column to order by), `:direction` (`:asc` or `:desc`), `:field_name`
      (the name of the field that is ordered by, or `nil`) and `:nulls` (`:default`, `:first`, `:last` or `:smallest`).
    * `:pagination` - a map with the keys `:page` and `:size`.
  """
  @callback list(criteria :: keyword(), fields :: list(), assigns :: map(), live_resource :: module()) :: {:ok, list()}

  @doc """
  Gets the total count of the current live_resource.
  Possibly being constrained the item query and the search- and filter options.
  """
  @callback count(criteria :: keyword(), fields :: list(), assigns :: map(), live_resource :: module()) ::
              {:ok, non_neg_integer()}

  @doc """
  Returns the data of a metric, such as the sum of a column, for the items matching the given criteria.

  Receives the same criteria as `c:count/4`.
  """
  @callback metric(
              metric :: map(),
              criteria :: keyword(),
              fields :: list(),
              assigns :: map(),
              live_resource :: module()
            ) ::
              {:ok, term()}

  @doc """
  Returns a new item that has not been saved yet, e.g. for the form of the `:new` action.
  """
  @callback new_item(assigns :: map(), live_resource :: module()) :: struct()

  @doc """
  Returns the association `name` of the resource, or `nil` if the resource has no such association.

  The returned map contains:

    * `:field` - the name of the association.
    * `:cardinality` - `:one` or `:many`.
    * `:owner_key` - the key of the resource the association is based on, e.g. `:user_id` for a `belongs_to :user`
      association.
    * `:through` - for an association through other associations, the associations it goes through, in order, as maps
      with the same keys. An empty list for any other association.
  """
  @callback association(name :: atom(), live_resource :: module()) :: map() | nil

  @doc """
  Returns the items that can be selected as the value of the association field `field`, e.g. the options of the select
  of a `Backpex.Fields.BelongsTo` field.

  The `:options_query` of the field and the following criteria limit the items:

    * `:ids` - only the items with these primary values. Values that are no valid primary value are ignored.
    * `:search` - only the items whose display field contains this string. Ignored if it is `nil`.
    * `:offset` and `:limit` - skip and limit the items.

  The `assigns` are passed to the `:options_query` of the field.
  """
  @callback list_options(field :: tuple(), criteria :: keyword(), assigns :: map(), live_resource :: module()) ::
              {:ok, list()}

  @doc """
  Returns the items of `c:list_options/4` for many assigns at once, e.g. for the index form of a
  `Backpex.Fields.BelongsTo` field in every row of the index view.

  Receives a map of keys to assigns and returns a map of the same keys to the items `c:list_options/4` returns for
  each assigns. Implement it to load equal items only once. Without it, `Backpex.Resource.list_options_by_key/4` calls
  `c:list_options/4` for every key.
  """
  @callback list_options_by_key(
              field :: tuple(),
              criteria :: keyword(),
              assigns_by_key :: map(),
              live_resource :: module()
            ) :: {:ok, map()}

  @doc """
  Returns the number of items `c:list_options/4` returns for the given criteria, ignoring `:offset` and `:limit`.
  """
  @callback count_options(field :: tuple(), criteria :: keyword(), assigns :: map(), live_resource :: module()) ::
              {:ok, non_neg_integer()}

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

  @optional_callbacks list_options_by_key: 4
end
