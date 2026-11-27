defmodule Backpex.Fields.OptionsQueryTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  alias Backpex.Fields.OptionsQuery

  defmodule User do
    @moduledoc false
    use Ecto.Schema

    schema "users" do
      field :name, :string
    end
  end

  # Returns the users it is configured with and sends the query to the test process.
  defmodule UsersRepo do
    @moduledoc false
    def all(query) do
      send(self(), {:all, query})

      Process.get(:users, [])
    end

    def aggregate(query, :count) do
      send(self(), {:aggregate, query})

      0
    end
  end

  @opts [repo: UsersRepo, queryable: User, label: :name, value: :id, search_by: :name]

  describe "list/3" do
    test "returns the options as label and value" do
      Process.put(:users, [%User{id: 1, name: "Anna"}, %User{id: 2, name: "Bert"}])

      assert User |> from() |> OptionsQuery.list([], @opts) == [{"Anna", 1}, {"Bert", 2}]
      assert_received {:all, %Ecto.Query{order_bys: [], limit: nil, offset: nil}}
    end

    test "orders a page by the value after the order of the options query" do
      query = User |> from() |> order_by([user], user.name)

      OptionsQuery.list(query, [offset: 2, limit: 2], @opts)

      assert_received {:all, %Ecto.Query{order_bys: [name_order, value_order], limit: limit, offset: offset}}
      assert Macro.to_string(name_order.expr) == "[asc: &0.name()]"
      assert Macro.to_string(value_order.expr) == "[asc: &0.id()]"
      assert %{params: [{2, :integer}]} = limit
      assert %{params: [{2, :integer}]} = offset
    end

    test "searches the field, ignoring case" do
      User |> from() |> OptionsQuery.list([search: "ann"], @opts)

      assert_received {:all, %Ecto.Query{wheres: [where]}}
      assert Macro.to_string(where.expr) == "ilike(&0.name(), ^0)"
      assert where.params == [{"%ann%", :string}]
    end

    test "searches a dynamic expression" do
      search_by = dynamic([user: user], fragment("upper(?)", user.name))

      opts = Keyword.put(@opts, :search_by, search_by)

      User |> from(as: :user) |> OptionsQuery.list([search: "ann"], opts)

      assert_received {:all, %Ecto.Query{wheres: [where]}}
      assert Macro.to_string(where.expr) =~ "ilike(fragment"
    end

    test "ignores a blank search" do
      User |> from() |> OptionsQuery.list([search: " "], @opts)

      assert_received {:all, %Ecto.Query{wheres: []}}
    end

    test "limits the options to the ids" do
      User |> from() |> OptionsQuery.list([ids: [1, 2]], @opts)

      assert_received {:all, %Ecto.Query{wheres: [where]}}
      assert Macro.to_string(where.expr) == "&0.id() in ^0"
    end
  end

  describe "page/3" do
    test "loads one option more than the page to tell whether more follow" do
      Process.put(:users, for(id <- 1..3, do: %User{id: id, name: "User #{id}"}))

      assert User |> from() |> OptionsQuery.page([limit: 2], @opts) == {[{"User 1", 1}, {"User 2", 2}], true}
      assert_received {:all, %Ecto.Query{limit: %{params: [{3, :integer}]}}}

      Process.put(:users, [%User{id: 1, name: "User 1"}])

      assert User |> from() |> OptionsQuery.page([limit: 2], @opts) == {[{"User 1", 1}], false}
    end

    test "loads every option without a limit" do
      Process.put(:users, [%User{id: 1, name: "User 1"}])

      assert User |> from() |> OptionsQuery.page([], @opts) == {[{"User 1", 1}], false}
      assert_received {:all, %Ecto.Query{limit: nil}}
    end
  end

  describe "count/3" do
    test "counts the options of the search" do
      User |> from() |> OptionsQuery.count([search: "ann"], @opts)

      assert_received {:aggregate, %Ecto.SubQuery{query: %Ecto.Query{wheres: [_where], limit: nil}}}
    end
  end
end
