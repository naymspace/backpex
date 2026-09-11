defmodule Backpex.Test.StubAdapter do
  @moduledoc """
  A `Backpex.Adapter` stand-in that performs no I/O.

  Every call reports back to the calling process as `{:adapter, function_name, ...}`, so a test can
  use `refute_received/1` to prove that a denied mutation never reached the data layer.
  """

  @doc """
  Reads one record from the fake store in `assigns.stub_records`, a map of primary value to record.

  `Backpex.Resource.reload/4` — and therefore every item action execution gate — goes through this,
  so a test can make a record change or vanish between selecting it and acting on it just by
  handing the gate a different store. A primary value the store does not know returns `{:ok, nil}`,
  which is what a deleted or out-of-scope row looks like.
  """
  def get(primary_value, _fields, assigns, _live_resource) do
    send(self(), {:adapter, :get, primary_value})

    {:ok, assigns |> Map.get(:stub_records, %{}) |> Map.get(primary_value)}
  end

  def change(item, attrs, _fields, _assigns, _live_resource, opts) do
    send(self(), {:adapter, :change, opts})

    {:changeset, item, attrs}
  end

  def insert({:changeset, item, attrs}, _live_resource) do
    send(self(), {:adapter, :insert, item, attrs})

    {:ok, item}
  end

  def update({:changeset, item, attrs}, _live_resource) do
    send(self(), {:adapter, :update, item, attrs})

    {:ok, item}
  end

  def delete_all(items, _live_resource) do
    send(self(), {:adapter, :delete_all, items})

    {:ok, items}
  end

  def update_all(items, updates, _live_resource) do
    send(self(), {:adapter, :update_all, items, updates})

    {length(items), nil}
  end
end

defmodule Backpex.Test.LiveResources do
  @moduledoc """
  Fake LiveResource modules with hand-written `can?/3` clauses, shared by the authorization, item
  action and resource tests.

  Each module implements only what `Backpex.Authorization`, `Backpex.Resource` and
  `Backpex.ItemAction` touch: `can?/3`, `config/1` for the adapter and the primary key, `fields/0`
  and `pubsub/0`. Tests that need the PubSub broadcasts have to start
  `{Phoenix.PubSub, name: #{inspect(__MODULE__)}.pubsub_server()}` themselves.
  """

  alias Backpex.Test.PubSub
  alias Backpex.Test.StubAdapter

  @pubsub_server PubSub
  @pubsub_topic "backpex_test"

  @doc "Name of the PubSub server every fake LiveResource in this module broadcasts on."
  def pubsub_server, do: @pubsub_server

  @doc "Topic every fake LiveResource in this module broadcasts on."
  def pubsub_topic, do: @pubsub_topic

  defmodule AllowAll do
    @moduledoc "Authorizes everything."
    def config(:adapter), do: StubAdapter
    def config(:primary_key), do: :id
    def fields, do: []
    def can?(_assigns, _action, _item), do: true
    def pubsub, do: [server: PubSub, topic: "backpex_test"]
  end

  defmodule DenyAll do
    @moduledoc "Denies everything."
    def config(:adapter), do: StubAdapter
    def config(:primary_key), do: :id
    def fields, do: []
    def can?(_assigns, _action, _item), do: false
    def pubsub, do: [server: PubSub, topic: "backpex_test"]
  end

  defmodule NoAdmins do
    @moduledoc "Denies every action on an item with `role: :admin`, allows everything else."
    def config(:adapter), do: StubAdapter
    def config(:primary_key), do: :id
    def fields, do: []
    def can?(_assigns, _action, %{role: :admin} = _item), do: false
    def can?(_assigns, _action, _item), do: true
    def pubsub, do: [server: PubSub, topic: "backpex_test"]
  end

  defmodule KeyAware do
    @moduledoc "Answers differently per action key, including a `nil` item."
    def config(:adapter), do: StubAdapter
    def config(:primary_key), do: :id
    def fields, do: []
    def can?(_assigns, :delete, %{role: :admin} = _item), do: false
    def can?(_assigns, :delete, _item), do: true
    def can?(_assigns, :new, nil), do: false
    def can?(_assigns, _action, _item), do: true
    def pubsub, do: [server: PubSub, topic: "backpex_test"]
  end

  defmodule OnlyCustomKey do
    @moduledoc "Authorizes `:custom_key` only, so tests can tell which action key was checked."
    def config(:adapter), do: StubAdapter
    def config(:primary_key), do: :id
    def fields, do: []
    def can?(_assigns, :custom_key, _item), do: true
    def can?(_assigns, _action, _item), do: false
    def pubsub, do: [server: PubSub, topic: "backpex_test"]
  end

  defmodule Recording do
    @moduledoc "Authorizes everything and reports each check as `{:can?, action, item}`."
    def config(:adapter), do: StubAdapter
    def config(:primary_key), do: :id
    def fields, do: []

    def can?(_assigns, action, item) do
      send(self(), {:can?, action, item})

      true
    end

    def pubsub, do: [server: PubSub, topic: "backpex_test"]
  end
end
