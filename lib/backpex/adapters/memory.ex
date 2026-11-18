# quokka:skip-module-directive-reordering
defmodule Backpex.Adapters.Memory do
  @config_schema [
    schema: [
      doc: """
      The `Ecto.Schema` of the items, e.g. an `embedded_schema`. It describes their fields (see
      `c:Backpex.Adapter.describe/2`) and builds their changesets for the forms.
      """,
      type: :atom,
      required: true
    ],
    store: [
      doc: "The name of the store that holds the items, see `start_link/1`.",
      type: :atom,
      required: true
    ],
    update_changeset: [
      doc: "The changeset function for updating items, see `Backpex.Adapters.Ecto`.",
      type: {:fun, 3},
      default: &Backpex.Adapters.Ecto.default_changeset/3
    ],
    create_changeset: [
      doc: "The changeset function for creating items, see `Backpex.Adapters.Ecto`.",
      type: {:fun, 3},
      default: &Backpex.Adapters.Ecto.default_changeset/3
    ]
  ]

  @moduledoc """
  A `Backpex.Adapter` that keeps the items of a LiveResource in memory, e.g. for prototypes, tests or data that comes
  from a file or another service.

  It only returns all items. It supports no part of a `Backpex.Query`, only writes (see `c:Backpex.Adapter.supports?/2`),
  so Backpex filters, searches, sorts, paginates and aggregates the items itself with `Backpex.Query.apply_to/2`. Relationships
  are not supported.

  Start a store for the items in your supervision tree and name it in the `adapter_config`:

      children = [
        {Backpex.Adapters.Memory, name: MyApp.Countries, items: MyApp.Countries.load()}
      ]

      use Backpex.LiveResource,
        adapter: Backpex.Adapters.Memory,
        adapter_config: [
          schema: MyApp.Country,
          store: MyApp.Countries,
          create_changeset: &MyApp.Country.changeset/3,
          update_changeset: &MyApp.Country.changeset/3
        ]

  The forms build changesets with the schema like `Backpex.Adapters.Ecto` does. A new item without a primary key gets
  the next integer for an `:id` or `:integer` key, or a UUID for a `:binary_id` or `Ecto.UUID` key. For a key of
  another type, e.g. a string, the changeset has to set it, or `c:Backpex.Adapter.insert/2` raises. The primary key is
  unique: a change to a key another item has is refused with an error on the key in the changeset.

  ## `adapter_config`

  #{NimbleOptions.docs(@config_schema)}

  > ### Work in progress {: .warning}
  >
  > The `Backpex.Adapters.Memory` is still under development and may change in future updates.
  """

  use Backpex.Adapter, config_schema: @config_schema, supports: [:insert, :update, :delete]
  use Agent

  alias Backpex.Query

  @doc """
  Starts a store with the given `:name` and `:items`.
  """
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    items = Keyword.get(opts, :items, [])

    Agent.start_link(fn -> items end, name: name)
  end

  @doc """
  Returns all items of the store.
  """
  def items(store), do: Agent.get(store, & &1)

  @doc """
  Replaces all items of the store.
  """
  def put_items(store, items) when is_list(items), do: Agent.update(store, fn _items -> items end)

  @impl Backpex.Adapter
  def read(%Query{from: [], resource: live_resource}), do: {:ok, items(store(live_resource))}

  def read(%Query{from: path}) do
    raise ArgumentError, "#{inspect(__MODULE__)} doesn't support relationships, got the path #{inspect(path)}"
  end

  @impl Backpex.Adapter
  def new_item(_assigns, live_resource), do: struct(live_resource.adapter_config(:schema))

  @impl Backpex.Adapter
  def describe([], live_resource) do
    schema = live_resource.adapter_config(:schema)

    %Backpex.Adapter.Description{
      primary_key: schema.__schema__(:primary_key),
      fields: :fields |> schema.__schema__() |> Map.new(&{&1, field_info(schema, &1)}),
      relationships: %{}
    }
  end

  def describe(_path, _live_resource), do: nil

  defp field_info(schema, name) do
    type = schema.__schema__(:type, name)
    cast_type = if type == :binary_id, do: Ecto.UUID, else: type

    %{type: cast_type, primitive: Ecto.Type.type(type)}
  end

  @impl Backpex.Adapter
  defdelegate change(item, attrs, fields, assigns, live_resource, opts), to: Backpex.Adapters.Ecto

  @impl Backpex.Adapter
  def put_assoc(_changeset, name, _value, _live_resource) do
    raise ArgumentError, "#{inspect(__MODULE__)} doesn't support relationships, got #{inspect(name)}"
  end

  @impl Backpex.Adapter
  def insert(changeset, live_resource) do
    with {:ok, item} <- Ecto.Changeset.apply_action(changeset, :insert) do
      primary_key = live_resource.config(:primary_key)
      # Raises here and not in the store, which would stop with it.
      generate = if is_nil(Map.fetch!(item, primary_key)), do: generator!(primary_key, live_resource)

      live_resource
      |> store()
      |> Agent.get_and_update(&insert_item(&1, item, generate, changeset, primary_key))
    end
  end

  defp insert_item(items, item, generate, changeset, primary_key) do
    item = if generate, do: Map.put(item, primary_key, generate.(items)), else: item

    if taken?(items, primary_key, item),
      do: {{:error, taken(changeset, primary_key, :insert)}, items},
      else: {{:ok, item}, Enum.concat(items, [item])}
  end

  @impl Backpex.Adapter
  def update(changeset, live_resource) do
    with {:ok, item} <- Ecto.Changeset.apply_action(changeset, :update) do
      primary_key = live_resource.config(:primary_key)
      # The stored item has the primary key the item had before the change, which may change it.
      stored_value = Map.fetch!(changeset.data, primary_key)
      stored? = &(Map.fetch!(&1, primary_key) == stored_value)

      live_resource
      |> store()
      |> Agent.get_and_update(&replace_item(&1, item, stored?, changeset, primary_key))
    end
  end

  defp replace_item(items, item, stored?, changeset, primary_key) do
    if items |> Enum.reject(stored?) |> taken?(primary_key, item),
      do: {{:error, taken(changeset, primary_key, :update)}, items},
      else: {{:ok, item}, Enum.map(items, &if(stored?.(&1), do: item, else: &1))}
  end

  defp taken?(items, primary_key, item) do
    value = Map.fetch!(item, primary_key)

    Enum.any?(items, &(Map.fetch!(&1, primary_key) == value))
  end

  # The error of a unique constraint of `Ecto.Changeset`, so forms show it like the one of a database.
  defp taken(changeset, primary_key, action) do
    changeset = Ecto.Changeset.add_error(changeset, primary_key, "has already been taken", constraint: :unique)

    %{changeset | action: action}
  end

  @impl Backpex.Adapter
  def update_all(items, changes, live_resource) do
    primary_key = live_resource.config(:primary_key)
    values = MapSet.new(items, &Map.fetch!(&1, primary_key))

    # The changes go into the stored items, so these keep what others changed since `items` were read.
    live_resource
    |> store()
    |> Agent.get_and_update(fn stored ->
      {stored, count} = Enum.map_reduce(stored, 0, &update_item(&1, &2, values, primary_key, changes))

      {{:ok, count}, stored}
    end)
  end

  defp update_item(item, count, values, primary_key, changes) do
    if MapSet.member?(values, Map.fetch!(item, primary_key)),
      do: {struct(item, changes), count + 1},
      else: {item, count}
  end

  @impl Backpex.Adapter
  def delete_all(items, live_resource) do
    primary_key = live_resource.config(:primary_key)
    values = MapSet.new(items, &Map.fetch!(&1, primary_key))

    deleted =
      live_resource
      |> store()
      |> Agent.get_and_update(fn stored ->
        Enum.split_with(stored, &MapSet.member?(values, Map.fetch!(&1, primary_key)))
      end)

    {:ok, deleted}
  end

  # Returns the function that generates the primary key of a new item from the stored items.
  defp generator!(primary_key, live_resource) do
    schema = live_resource.adapter_config(:schema)

    case schema.__schema__(:type, primary_key) do
      type when type in [:id, :integer] ->
        &next_integer(&1, primary_key)

      type when type in [:binary_id, Ecto.UUID] ->
        fn _items -> Ecto.UUID.generate() end

      type ->
        raise ArgumentError, """
        #{inspect(__MODULE__)} can't generate the primary key #{inspect(primary_key)} of #{inspect(schema)}, as its \
        type is #{inspect(type)}. It generates integers (:id and :integer) and UUIDs (:binary_id and Ecto.UUID). Set \
        the key in the changeset, e.g. in the :create_changeset of the adapter_config.
        """
    end
  end

  defp next_integer(items, primary_key) do
    items
    |> Enum.map(&Map.fetch!(&1, primary_key))
    |> Enum.filter(&is_integer/1)
    |> Enum.max(fn -> 0 end)
    |> Kernel.+(1)
  end

  defp store(live_resource), do: live_resource.adapter_config(:store)
end
