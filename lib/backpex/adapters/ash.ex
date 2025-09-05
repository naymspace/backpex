if Code.ensure_loaded?(Ash) do
  defmodule Backpex.Adapters.Ash do
    @config_schema [
      resource: [
        doc: "The `Ash.Resource` that will be used to perform CRUD operations.",
        type: :atom,
        required: true
      ]
    ]

    @moduledoc """
    The `Backpex.Adapter` to connect your `Backpex.LiveResource` to an `Ash.Resource`.

    ## `adapter_config`

    #{NimbleOptions.docs(@config_schema)}

    > ### Work in progress {: .error}
    >
    > The `Backpex.Adapters.Ash` is currently not usable! It can barely list and show items. We will work on this as we continue to implement  the `Backpex.Adapter` pattern throughout the codebase.
    """

    use Backpex.Adapter, config_schema: @config_schema
    require Ash.Query

    @doc """
    Gets a database record with the given primary key value.

    Returns `nil` if no result was found.
    """
    @impl Backpex.Adapter
    def get(primary_value, _assigns, live_resource, _fields) do
      resource = live_resource.adapter_config(:resource)
      primary_key = live_resource.config(:primary_key)

      resource
      |> Ash.Query.filter(^Ash.Expr.ref(primary_key) == ^primary_value)
      |> Ash.read_one()
    end

    @doc """
    Returns a list of items by given criteria.
    """
    @impl Backpex.Adapter
    def list(_criteria, _assigns, live_resource, _fields) do
      live_resource.adapter_config(:resource)
      |> Ash.read()
    end

    @doc """
    Returns the number of items matching the given criteria.
    """
    @impl Backpex.Adapter
    def count(_criteria, _assigns, live_resource, _fields) do
      live_resource.adapter_config(:resource)
      |> Ash.count()
    end

    @doc """
    Deletes multiple items.
    """
    @impl Backpex.Adapter
    def delete_all(items, live_resource) do
      primary_key = live_resource.config(:primary_key)
      ids = Enum.map(items, &Map.fetch!(&1, primary_key))

      result =
        live_resource.adapter_config(:resource)
        |> Ash.Query.filter(^Ash.Expr.ref(primary_key) in ^ids)
        |> Ash.bulk_destroy(:destroy, %{}, return_records?: true)

      {:ok, result.records}
    end

    @doc """
    Inserts given item.
    """
    @impl Backpex.Adapter
    def insert(_item, _live_resource) do
      raise "not implemented yet"
    end

    @doc """
    Updates given item.
    """
    @impl Backpex.Adapter
    def update(_item, _live_resource) do
      raise "not implemented yet"
    end

    @doc """
    Updates given items.
    """
    @impl Backpex.Adapter
    def update_all(_items, _updates, _live_resource) do
      raise "not implemented yet"
    end

    @doc """
    Applies a change to a given item.
    """
    @impl Backpex.Adapter
    def change(_item, _attrs, _fields, _assigns, _live_resource, _opts) do
      raise "not implemented yet"
    end
  end
end
