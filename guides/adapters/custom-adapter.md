# Custom Adapter

A LiveResource reads and writes its items through an adapter, see `Backpex.Adapter`. `Backpex.Adapters.Ecto` is the
default. Write your own adapter to show items of another data source, e.g. a CSV file or an HTTP API.

Backpex builds a `Backpex.Query` for every read: the items of the index view, a single item, the number of items, the
data of metrics and the options of association fields. An adapter runs the parts of the query its data source can run
and tells Backpex which parts these are with `c:Backpex.Adapter.supports?/2`. Backpex applies the other parts to the
items in memory with `Backpex.Query.apply_to/2`. So the smallest adapter only returns all items.

## A read-only CSV adapter

The adapter below shows the rows of a CSV file. It describes the items with an `Ecto.Schema`, so Backpex can cast the
values of filters and the forms could build changesets, and returns all rows from `c:Backpex.Adapter.read/1`. It
supports no part of the query, so Backpex filters, searches, sorts and paginates the rows itself. It doesn't support
writes either, so Backpex hides the actions to create, edit and delete rows and refuses them.

```elixir
defmodule MyApp.CsvAdapter do
  use Backpex.Adapter,
    config_schema: [
      path: [doc: "The path of the CSV file.", type: :string, required: true],
      schema: [doc: "The schema of a row.", type: :atom, required: true]
    ],
    supports: []

  @impl Backpex.Adapter
  def read(%Backpex.Query{from: [], resource: live_resource}) do
    schema = live_resource.adapter_config(:schema)
    [header | rows] = live_resource.adapter_config(:path) |> File.read!() |> String.split("\n", trim: true)
    names = header |> String.split(",") |> Enum.map(&String.to_existing_atom/1)

    items =
      Enum.map(rows, fn row ->
        attrs = names |> Enum.zip(String.split(row, ",")) |> Map.new()
        schema |> struct() |> Ecto.Changeset.cast(attrs, names) |> Ecto.Changeset.apply_changes()
      end)

    {:ok, items}
  end

  @impl Backpex.Adapter
  def describe([], live_resource) do
    schema = live_resource.adapter_config(:schema)

    %Backpex.Adapter.Description{
      primary_key: schema.__schema__(:primary_key),
      fields:
        Map.new(schema.__schema__(:fields), fn name ->
          type = schema.__schema__(:type, name)
          {name, %{type: type, primitive: Ecto.Type.type(type)}}
        end),
      relationships: %{}
    }
  end

  def describe(_path, _live_resource), do: nil

  @impl Backpex.Adapter
  def new_item(_assigns, live_resource), do: struct(live_resource.adapter_config(:schema))

  @impl Backpex.Adapter
  def change(item, attrs, _fields, _assigns, _live_resource, _opts), do: Ecto.Changeset.cast(item, attrs, [])

  @impl Backpex.Adapter
  def insert(_changeset, _live_resource), do: {:error, :read_only}

  @impl Backpex.Adapter
  def update(_changeset, _live_resource), do: {:error, :read_only}

  @impl Backpex.Adapter
  def update_all(_items, _changes, _live_resource), do: {:error, :read_only}

  @impl Backpex.Adapter
  def delete_all(_items, _live_resource), do: {:error, :read_only}

  @impl Backpex.Adapter
  def put_assoc(changeset, _name, _value, _live_resource), do: changeset
end
```

The schema of a row is an embedded schema:

```elixir
defmodule MyApp.Country do
  use Ecto.Schema

  @primary_key {:code, :string, autogenerate: false}
  embedded_schema do
    field :name, :string
    field :population, :integer
  end
end
```

Use the adapter in a LiveResource:

```elixir
defmodule MyAppWeb.CountryLive do
  use Backpex.LiveResource,
    adapter: MyApp.CsvAdapter,
    adapter_config: [path: "priv/countries.csv", schema: MyApp.Country],
    primary_key: :code

  # ...
end
```

The write callbacks only return errors, as Backpex never calls them: `Backpex.Authorization` denies the `:new`,
`:edit` and `:delete` actions for an adapter that doesn't support `:insert`, `:update` and `:delete`.

## Running parts of the query

To run parts of the query in the data source, e.g. a filter in the query string of an HTTP API, list them in the
`:supports` option of `use Backpex.Adapter` or implement `c:Backpex.Adapter.supports?/2`. Backpex then leaves them to
the adapter: `:filter` (with `{:filter, operator}` for single operators such as `:contains` or `:exists`), `:search`,
`:sort`, `:offset`, `:limit`, `:load`, `:count` and `:aggregate`. `:insert`, `:update` and `:delete` enable the writes. A part the adapter doesn't support, and every part that
depends on it, is applied in memory. For example, an adapter that sorts but can't filter gets a query without the
filter and the sort, as the items have to be filtered before they are sorted.

## Writing items

Forms are built from an `Ecto.Changeset` for every data source: `c:Backpex.Adapter.change/6` returns one, e.g. from an
embedded schema, and `c:Backpex.Adapter.insert/2` and `c:Backpex.Adapter.update/2` write the item it describes.
`c:Backpex.Adapter.update_all/3` sets fields to values in many items, e.g. `%{deleted_at: now}`, and
`c:Backpex.Adapter.delete_all/2` deletes items.

See `Backpex.Adapters.Memory` for an adapter that keeps items in memory and writes them, too.
