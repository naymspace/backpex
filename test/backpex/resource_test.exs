defmodule Backpex.ResourceTest do
  use ExUnit.Case, async: true

  import Backpex.Expr, only: [expr: 1]

  alias Backpex.Expr.Call
  alias Backpex.Metrics.Value
  alias Backpex.Query
  alias Backpex.Resource
  alias Backpex.Test.LiveResources
  alias Backpex.Test.LiveResources.AllowAll
  alias Backpex.Test.LiveResources.DenyAll
  alias Backpex.Test.LiveResources.NoAdmins
  alias Backpex.Test.LiveResources.OnlyCustomKey
  alias Backpex.Test.LiveResources.Recording
  alias Phoenix.LiveView.Socket

  setup do
    start_supervised!({Phoenix.PubSub, name: LiveResources.pubsub_server()})
    :ok = Phoenix.PubSub.subscribe(LiveResources.pubsub_server(), LiveResources.pubsub_topic())

    %{assigns: %{some: :assign}, item: %{id: 1}, fields: []}
  end

  describe "insert/6" do
    test "authorizes :new with a nil item before building the changeset", %{assigns: assigns, item: item, fields: f} do
      assert {:ok, ^item} = Resource.insert(item, %{}, f, assigns, Recording)

      assert_received {:can?, :new, nil}
    end

    test "raises before change/6 when not authorized", %{assigns: assigns, item: item, fields: f} do
      assert_raise Backpex.ForbiddenError, fn ->
        Resource.insert(item, %{}, f, assigns, DenyAll)
      end

      refute_received {:adapter, :change, _opts}
      refute_received {:adapter, :insert, _item, _attrs}
    end

    test "broadcasts on success", %{assigns: assigns, item: item, fields: f} do
      assert {:ok, ^item} = Resource.insert(item, %{}, f, assigns, AllowAll)

      assert_received {"created", ^item}
      assert_received {"backpex:created", ^item}
    end

    test "honors :authorization_action", %{assigns: assigns, item: item, fields: f} do
      assert_raise Backpex.ForbiddenError, fn ->
        Resource.insert(item, %{}, f, assigns, OnlyCustomKey)
      end

      assert {:ok, ^item} =
               Resource.insert(item, %{}, f, assigns, OnlyCustomKey, authorization_action: :custom_key)
    end

    test "honors authorize?: false", %{assigns: assigns, item: item, fields: f} do
      assert {:ok, ^item} = Resource.insert(item, %{}, f, assigns, DenyAll, authorize?: false)

      assert_received {:adapter, :insert, ^item, _attrs}
    end

    test "does not leak authorization options into change/6", %{assigns: assigns, item: item, fields: f} do
      opts = [authorization_action: :custom_key, authorize?: true, assocs: [tags: []]]

      assert {:ok, ^item} = Resource.insert(item, %{}, f, assigns, OnlyCustomKey, opts)

      assert_received {:adapter, :change, change_opts}
      refute Keyword.has_key?(change_opts, :authorization_action)
      refute Keyword.has_key?(change_opts, :authorize?)
      assert Keyword.get(change_opts, :assocs) == [tags: []]
      assert Keyword.get(change_opts, :action) == :insert
    end

    test "raises when :authorize? is not a boolean", %{assigns: assigns, item: item, fields: f} do
      assert_raise ArgumentError, fn ->
        Resource.insert(item, %{}, f, assigns, AllowAll, authorize?: :nope)
      end
    end

    test "raises when :authorization_action is nil and never reaches the adapter", %{
      assigns: assigns,
      item: item,
      fields: f
    } do
      # `Keyword.pop/3` hands back an explicitly passed `nil` instead of the default, and `nil` is
      # an atom — so without validation this would check `can?(assigns, nil, item)`, which a
      # permissive catch-all clause happily authorizes.
      assert_raise ArgumentError, ~r/:authorization_action/, fn ->
        Resource.insert(item, %{}, f, assigns, DenyAll, authorization_action: nil)
      end

      refute_received {:adapter, :change, _opts}
      refute_received {:adapter, :insert, _item, _attrs}
    end

    test "raises when :authorization_action is not an atom", %{assigns: assigns, item: item, fields: f} do
      assert_raise ArgumentError, ~r/:authorization_action/, fn ->
        Resource.insert(item, %{}, f, assigns, AllowAll, authorization_action: "custom_key")
      end
    end
  end

  describe "update/6" do
    test "authorizes :edit with the item", %{assigns: assigns, item: item, fields: f} do
      assert {:ok, ^item} = Resource.update(item, %{}, f, assigns, Recording)

      assert_received {:can?, :edit, ^item}
    end

    test "raises before change/6 when not authorized", %{assigns: assigns, item: item, fields: f} do
      assert_raise Backpex.ForbiddenError, fn ->
        Resource.update(item, %{}, f, assigns, DenyAll)
      end

      refute_received {:adapter, :change, _opts}
      refute_received {:adapter, :update, _item, _attrs}
    end

    test "broadcasts on success", %{assigns: assigns, item: item, fields: f} do
      assert {:ok, ^item} = Resource.update(item, %{}, f, assigns, AllowAll)

      assert_received {"updated", ^item}
      assert_received {"backpex:updated", ^item}
    end

    test "honors :authorization_action and authorize?: false", %{assigns: assigns, item: item, fields: f} do
      assert {:ok, ^item} =
               Resource.update(item, %{}, f, assigns, OnlyCustomKey, authorization_action: :custom_key)

      assert {:ok, ^item} = Resource.update(item, %{}, f, assigns, DenyAll, authorize?: false)
    end
  end

  describe "reload/4" do
    test "returns the current records, in the order they were given", %{fields: f} do
      fresh = [%{id: 1, role: :admin}, %{id: 2, role: :user}]
      assigns = %{stub_records: Map.new(fresh, &{&1.id, &1})}

      stale = [%{id: 1, role: :user}, %{id: 2, role: :user}]

      assert Resource.reload(stale, f, assigns, AllowAll) == fresh
    end

    test "keeps a vanished record as nil in its position", %{fields: f} do
      assigns = %{stub_records: %{2 => %{id: 2, role: :user}}}

      items = [%{id: 1, role: :user}, %{id: 2, role: :user}, %{id: 3, role: :user}]

      assert Resource.reload(items, f, assigns, AllowAll) == [nil, %{id: 2, role: :user}, nil]
    end

    test "a nil entry stays nil and is not looked up", %{fields: f} do
      assigns = %{stub_records: %{}}

      assert Resource.reload([nil], f, assigns, AllowAll) == [nil]

      refute_received {:adapter, :get, _primary_value}
    end

    test "reads by primary value, not by identity", %{fields: f} do
      assigns = %{stub_records: %{7 => %{id: 7}}}

      assert Resource.reload([%{id: 7, stale: true}], f, assigns, AllowAll) == [%{id: 7}]

      assert_received {:adapter, :get, 7}
    end

    test "is a read and never authorizes", %{fields: f} do
      assigns = %{stub_records: %{1 => %{id: 1}}}

      assert Resource.reload([%{id: 1}], f, assigns, DenyAll) == [%{id: 1}]
    end

    test "does not touch the adapter for an empty list", %{fields: f} do
      assert Resource.reload([], f, %{}, AllowAll) == []

      refute_received {:adapter, :get, _primary_value}
    end
  end

  describe "delete_all/4" do
    test "authorizes :delete per item", %{assigns: assigns} do
      items = [%{id: 1}, %{id: 2}]

      assert {:ok, ^items} = Resource.delete_all(items, assigns, Recording)

      assert_received {:can?, :delete, %{id: 1}}
      assert_received {:can?, :delete, %{id: 2}}
    end

    test "raises for the whole call when a single item is unauthorized", %{assigns: assigns} do
      items = [%{id: 1, role: :user}, %{id: 2, role: :admin}]

      assert_raise Backpex.ForbiddenError, fn ->
        Resource.delete_all(items, assigns, NoAdmins)
      end

      refute_received {:adapter, :delete_all, _items}
    end

    test "raises NoResultsError when the list contains nil", %{assigns: assigns} do
      assert_raise Backpex.NoResultsError, fn ->
        Resource.delete_all([%{id: 1}, nil], assigns, AllowAll)
      end

      refute_received {:adapter, :delete_all, _items}
    end

    test "raises when :authorization_action is nil and never reaches the adapter", %{assigns: assigns} do
      assert_raise ArgumentError, ~r/:authorization_action/, fn ->
        Resource.delete_all([%{id: 1}], assigns, DenyAll, authorization_action: nil)
      end

      refute_received {:adapter, :delete_all, _items}
    end

    test "passes an empty list vacuously", %{assigns: assigns} do
      assert {:ok, []} = Resource.delete_all([], assigns, DenyAll)

      assert_received {:adapter, :delete_all, []}
    end

    test "honors :authorization_action and authorize?: false", %{assigns: assigns} do
      items = [%{id: 1}]

      assert {:ok, ^items} = Resource.delete_all(items, assigns, OnlyCustomKey, authorization_action: :custom_key)
      assert {:ok, ^items} = Resource.delete_all(items, assigns, DenyAll, authorize?: false)
    end

    test "broadcasts a deleted event per item", %{assigns: assigns} do
      item = %{id: 1}

      assert {:ok, _items} = Resource.delete_all([item], assigns, AllowAll)

      assert_received {"deleted", ^item}
      assert_received {"backpex:deleted", ^item}
    end

    test "returns the error of the adapter without broadcasting", %{assigns: assigns} do
      assert Resource.delete_all([%{id: 1, referenced?: true}], assigns, AllowAll) == {:error, :foreign_key_violation}

      refute_received {"deleted", _item}
      refute_received {"backpex:deleted", _item}
    end

    test "does not answer the pre-0.21 delete_all/2 signature" do
      # The arguments go through a variable so the compiler's type checker does not flag the
      # intentionally wrong call — what is under test is the runtime behavior.
      args = [[%{id: 1}], AllowAll]

      assert_raise UndefinedFunctionError, fn ->
        apply(Resource, :delete_all, args)
      end
    end

    test "refuses a socket where assigns are expected" do
      # Passing the socket instead of its assigns would authorize against the wrong context. The
      # `is_map/1` + `not is_struct/1` guard makes that a hard error rather than a silent mismatch.
      args = [[%{id: 1}], %Socket{}, DenyAll]

      assert_raise FunctionClauseError, fn ->
        apply(Resource, :delete_all, args)
      end

      refute_received {:adapter, :delete_all, _items}
    end
  end

  describe "update_all/5" do
    test "authorizes :edit per item", %{assigns: assigns} do
      items = [%{id: 1}, %{id: 2}]

      assert {:ok, ^items} = Resource.update_all(items, [set: [x: 1]], assigns, Recording)

      assert_received {:can?, :edit, %{id: 1}}
      assert_received {:can?, :edit, %{id: 2}}
    end

    test "raises for the whole call when a single item is unauthorized", %{assigns: assigns} do
      items = [%{id: 1, role: :user}, %{id: 2, role: :admin}]

      assert_raise Backpex.ForbiddenError, fn ->
        Resource.update_all(items, [set: [x: 1]], assigns, NoAdmins)
      end

      refute_received {:adapter, :update_all, _items, _updates}
    end

    test "raises NoResultsError when the list contains nil", %{assigns: assigns} do
      assert_raise Backpex.NoResultsError, fn ->
        Resource.update_all([%{id: 1}, nil], [set: [x: 1]], assigns, AllowAll)
      end

      refute_received {:adapter, :update_all, _items, _updates}
    end

    test "passes an empty list vacuously", %{assigns: assigns} do
      assert {:ok, []} = Resource.update_all([], [set: [x: 1]], assigns, DenyAll)
    end

    test "broadcasts the default event", %{assigns: assigns} do
      item = %{id: 1}

      assert {:ok, _items} = Resource.update_all([item], [set: [x: 1]], assigns, AllowAll)

      assert_received {"updated", ^item}
      assert_received {"backpex:updated", ^item}
    end

    test "honors :event_name", %{assigns: assigns} do
      item = %{id: 1}

      assert {:ok, _items} = Resource.update_all([item], [set: [x: 1]], assigns, AllowAll, event_name: "deleted")

      assert_received {"deleted", ^item}
      assert_received {"backpex:deleted", ^item}
    end

    test "honors :authorization_action and authorize?: false", %{assigns: assigns} do
      items = [%{id: 1}]

      assert {:ok, ^items} =
               Resource.update_all(items, [set: [x: 1]], assigns, OnlyCustomKey, authorization_action: :custom_key)

      assert {:ok, ^items} = Resource.update_all(items, [set: [x: 1]], assigns, DenyAll, authorize?: false)
    end

    test "does not answer the pre-0.21 update_all/3 signature" do
      # The old head had `event_name \\ "updated"`, so it defined an arity-3 function too.
      args = [[%{id: 1}], [set: [x: 1]], AllowAll]

      assert_raise UndefinedFunctionError, fn ->
        apply(Resource, :update_all, args)
      end
    end

    test "raises FunctionClauseError for the pre-0.21 update_all/4 signature", %{assigns: _assigns} do
      # `update_all(items, updates, "deleted", MyLive)` has the same arity as the new
      # `update_all(items, updates, assigns, live_resource)`. The `is_map(assigns)` guard makes the
      # old call fail loudly instead of silently authorizing against a string.
      args = [[%{id: 1}], [set: [x: 1]], "deleted", AllowAll]

      assert_raise FunctionClauseError, fn ->
        apply(Resource, :update_all, args)
      end
    end
  end

  describe "read_by_key/1" do
    defmodule KeyAdapter do
      @moduledoc false
      def read(query) do
        send(self(), {:read, query.limit})
        {:ok, [query.limit]}
      end
    end

    defmodule KeyLive do
      @moduledoc false
      def config(:adapter), do: KeyAdapter
    end

    test "reads equal queries once, whatever their context" do
      queries = %{
        a: KeyLive |> Query.new(%{assigns: %{key: :a}}) |> Query.limit(1),
        b: KeyLive |> Query.new(%{assigns: %{key: :b}}) |> Query.limit(1),
        c: KeyLive |> Query.new() |> Query.limit(2)
      }

      assert Resource.read_by_key(queries) == {:ok, %{a: [1], b: [1], c: [2]}}
      assert_received {:read, 1}
      assert_received {:read, 2}
      refute_received {:read, _limit}
    end
  end

  describe "read/1, count/1 and aggregate/1 with an adapter that supports some parts of a query" do
    defmodule FilterOnlyAdapter do
      @moduledoc false
      # Runs the filter, but nothing after it, and reports the query it gets.
      use Backpex.Adapter, supports: [:filter]

      def read(query) do
        send(self(), {:read, query})

        items = [%{id: 1, likes: 3}, %{id: 2, likes: 1}, %{id: 3, likes: 2}, %{id: 4, likes: 9}]
        {:ok, Enum.reject(items, &(query.filter && &1.likes > 5))}
      end

      def describe(_path, _live_resource) do
        %Backpex.Adapter.Description{
          primary_key: [:id],
          fields: %{id: %{type: :id, primitive: :id}, likes: %{type: :integer, primitive: :integer}},
          relationships: %{}
        }
      end
    end

    defmodule FilterOnlyLive do
      @moduledoc false
      def config(:adapter), do: FilterOnlyAdapter
    end

    setup do
      %{query: FilterOnlyLive |> Query.new() |> Query.filter(expr(likes <= 5))}
    end

    test "leaves the filter to the adapter and sorts, skips and limits the items in memory", %{query: query} do
      query = query |> Query.sort(likes: :desc) |> Query.offset(1) |> Query.limit(1)

      assert {:ok, [%{id: 3}]} = Resource.read(query)
      assert_received {:read, %Query{filter: %Call{}, sort: [], offset: nil, limit: nil}}
    end

    test "counts and aggregates the items in memory without the callbacks", %{query: query} do
      assert Resource.count(query) == {:ok, 3}
      assert query |> Query.aggregate(:likes, {:sum, :likes}) |> Resource.aggregate() == {:ok, %{likes: 6}}
    end

    test "leaves a filter to an adapter that supports each of its operators" do
      defmodule LessOrEqualAdapter do
        @moduledoc false
        use Backpex.Adapter, supports: [{:filter, :<=}, :sort, :offset, :limit]

        defdelegate describe(path, live_resource), to: FilterOnlyAdapter

        def read(query) do
          send(self(), {:read, query})
          {:ok, [%{id: 1, likes: 3}]}
        end
      end

      defmodule LessOrEqualLive do
        @moduledoc false
        def config(:adapter), do: LessOrEqualAdapter
      end

      query = LessOrEqualLive |> Query.new() |> Query.filter(expr(likes <= 5)) |> Query.limit(1)

      assert {:ok, [%{id: 1}]} = Resource.read(query)
      assert_received {:read, %Query{filter: %Call{name: :<=}, limit: 1}}
    end

    test "loads the relationships of the paths the filter in memory reads" do
      defmodule NoFilterAdapter do
        @moduledoc false
        use Backpex.Adapter, supports: [:load]

        def read(query) do
          send(self(), {:read, query})
          {:ok, [%{id: 1, author: %{name: "Ann"}, tags: [%{category: %{name: "lang"}}]}]}
        end
      end

      defmodule NoFilterLive do
        @moduledoc false
        def config(:adapter), do: NoFilterAdapter
      end

      # Built without `Backpex.Query.filter/2`, as this adapter describes no relationships to cast with.
      filter = Backpex.Expr.all([expr(author.name == "Ann"), expr(exists(tags, category.name == "lang"))])
      query = %{Query.new(NoFilterLive) | filter: filter}

      assert {:ok, [%{id: 1}]} = Resource.read(query)
      assert_received {:read, %Query{filter: nil, load: load}}
      assert Enum.sort(load) == [:author, tags: [:category]]
    end

    test "applies the filter in memory if the adapter doesn't support one of its operators" do
      defmodule NoInAdapter do
        @moduledoc false
        use Backpex.Adapter, supports: [{:filter, :<=}, :sort]

        defdelegate describe(path, live_resource), to: FilterOnlyAdapter

        def read(query) do
          send(self(), {:read, query})
          {:ok, [%{id: 1, likes: 3}, %{id: 2, likes: 1}]}
        end
      end

      defmodule NoInLive do
        @moduledoc false
        def config(:adapter), do: NoInAdapter
      end

      query = NoInLive |> Query.new() |> Query.filter(expr(likes in [1, 2])) |> Query.sort(likes: :asc)

      assert {:ok, [%{id: 2}]} = Resource.read(query)
      assert_received {:read, %Query{filter: nil, sort: []}}
    end
  end

  describe "read/1 and count/1" do
    test "don't call the adapter for an invalid query" do
      query = KeyLive |> Query.new() |> Query.put_error(:invalid)

      assert Resource.read(query) == {:ok, []}
      assert Resource.count(query) == {:ok, 0}
      refute_received {:read, _limit}
    end
  end

  describe "metrics/3" do
    defmodule MetricAdapter do
      @moduledoc false
      def aggregate(query), do: {:ok, Map.new(query.aggregates, &{&1.name, {:adapter, &1.aggregate, query.limit}})}
    end

    defmodule MetricLive do
      @moduledoc false
      def config(:adapter), do: MetricAdapter
    end

    defmodule DataMetric do
      @moduledoc false
      @behaviour Backpex.Metric

      @impl Backpex.Metric
      def render(assigns), do: assigns

      @impl Backpex.Metric
      def format(data, _format), do: data

      @impl Backpex.Metric
      def data(metric, query, assigns), do: {:data, metric.label, query.search, query.limit, assigns.current_user}
    end

    test "calls data/3 of the metric module with the query of all pages and the assigns instead of the adapter" do
      query = MetricLive |> Query.new() |> Query.search("Ann", []) |> Query.limit(10)

      assert Resource.metrics([balance: %{module: DataMetric, label: "Balance"}], query, %{current_user: :ann}) ==
               %{balance: {:data, "Balance", %{term: "Ann", targets: []}, nil, :ann}}
    end

    test "raises for a metric module that still implements query/3" do
      defmodule QueryMetric do
        @moduledoc false
        def query(query, _select, _repo), do: query
      end

      assert_raise ArgumentError, ~r/implements query\/3, but metrics no longer query their data/, fn ->
        Resource.metrics([balance: %{module: QueryMetric, label: "Balance"}], Query.new(MetricLive), %{})
      end
    end

    test "raises for a metric module that still implements data/2" do
      defmodule LegacyDataMetric do
        @moduledoc false
        def data(_metric, _assigns), do: 1
      end

      assert_raise ArgumentError, ~r/implements data\/2, but Backpex calls Backpex.Metric.data\/3/, fn ->
        Resource.metrics([balance: %{module: LegacyDataMetric, label: "Balance"}], Query.new(MetricLive), %{})
      end
    end

    test "lets the adapter compute the other metrics in one call, on all pages" do
      metrics = [
        total: %{module: Value, label: "Total", aggregate: :count},
        sum: %{module: Value, label: "Sum", aggregate: {:sum, :amount}}
      ]

      query = MetricLive |> Query.new() |> Query.limit(10)

      assert Resource.metrics(metrics, query, %{}) == %{
               total: {:adapter, :count, nil},
               sum: {:adapter, {:sum, :amount}, nil}
             }
    end
  end
end
