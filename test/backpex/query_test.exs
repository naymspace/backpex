defmodule Backpex.QueryTest do
  use ExUnit.Case, async: true

  import Backpex.Expr, only: [expr: 1]

  alias Backpex.Expr
  alias Backpex.Query

  doctest Backpex.Query

  defmodule Author do
    use Ecto.Schema

    schema "authors" do
      field :name, :string
    end
  end

  defmodule Article do
    use Ecto.Schema

    @primary_key {:id, :binary_id, autogenerate: true}
    schema "articles" do
      field :title, :string
      field :likes, :integer
      belongs_to :author, Backpex.QueryTest.Author
    end
  end

  defmodule ArticleLive do
    @moduledoc false
    def config(:adapter), do: Backpex.Adapters.Ecto
    def config(:primary_key), do: :id
    def adapter_config(:schema), do: Backpex.QueryTest.Article
  end

  describe "filter/2" do
    test "casts the values and adds the expressions with and" do
      query =
        ArticleLive
        |> Query.new()
        |> Query.filter(expr(likes >= "10"))
        |> Query.filter(nil)
        |> Query.filter(title: "Elixir")

      assert query.filter == Expr.all([expr(likes >= 10), expr(title == "Elixir")])
    end

    test "casts the fields of the related items of from/2" do
      query = ArticleLive |> Query.new() |> Query.from([:author]) |> Query.filter(expr(id == "1"))

      assert query.filter == expr(id == 1)
    end

    test "raises for an unknown field" do
      assert_raise ArgumentError, ~r/unknown field :unknown/, fn ->
        ArticleLive |> Query.new() |> Query.filter(expr(unknown == 1))
      end
    end
  end

  describe "primary/2 and primary_in/2" do
    test "keep the items with the primary values" do
      uuid = Ecto.UUID.generate()

      assert ArticleLive |> Query.new() |> Query.primary(uuid) |> Map.fetch!(:filter) == expr(id == ^uuid)

      assert ArticleLive
             |> Query.new()
             |> Query.from([:author])
             |> Query.primary_in(["1", "two", nil, 3])
             |> Map.fetch!(:filter) == expr(id in [1, 3])
    end

    test "make the query invalid for a primary value that can't be cast" do
      query = ArticleLive |> Query.new() |> Query.primary("not a uuid")

      refute query.valid?
      assert query.errors == [{:invalid_primary_value, "not a uuid"}]
      assert query.filter == nil
    end
  end

  describe "search/3" do
    test "takes names, paths and refs as targets" do
      query = ArticleLive |> Query.new() |> Query.search("eli", [:title, "author.name", Expr.ref(:likes)])

      assert query.search == %{
               term: "eli",
               targets: [Expr.ref(:title), Expr.ref([:author], :name), Expr.ref(:likes)]
             }
    end

    test "removes the search for a blank term" do
      query = ArticleLive |> Query.new() |> Query.search("eli", [:title])

      assert query |> Query.search("  ", [:title]) |> Map.fetch!(:search) == nil
      assert query |> Query.search(nil, [:title]) |> Map.fetch!(:search) == nil
    end
  end

  describe "sort/2 and default_sort/2" do
    test "apply the default sort only without a sort" do
      query = ArticleLive |> Query.new() |> Query.default_sort(likes: :desc_nulls_last)

      assert Query.sorts(query) == [{Expr.ref(:likes), :desc_nulls_last}]

      query = Query.sort(query, [{"author.name", :asc}])
      assert Query.sorts(query) == [{Expr.ref([:author], :name), :asc}]
    end

    test "raise for an unknown direction" do
      assert_raise ArgumentError, ~r/expected a field and a direction/, fn ->
        ArticleLive |> Query.new() |> Query.sort(title: :up)
      end
    end
  end

  describe "aggregate/4" do
    test "adds named aggregates with a cast where expression" do
      query =
        ArticleLive
        |> Query.new()
        |> Query.aggregate(:total, :count)
        |> Query.aggregate(:liked, {:sum, :likes}, where: expr(likes > "5"))

      assert query.aggregates == [
               %{name: :total, aggregate: :count, where: nil},
               %{name: :liked, aggregate: {:sum, :likes}, where: expr(likes > 5)}
             ]
    end

    test "raises for an unknown aggregate" do
      assert_raise ArgumentError, ~r/expected an aggregate/, fn ->
        ArticleLive |> Query.new() |> Query.aggregate(:median, {:median, :likes})
      end
    end
  end

  describe "unset/2" do
    test "removes the given parts and keeps the others" do
      query =
        ArticleLive
        |> Query.new()
        |> Query.filter(title: "Elixir")
        |> Query.sort(title: :asc)
        |> Query.limit(10)
        |> Query.offset(20)
        |> Query.unset([:sort, :limit, :offset])

      assert %{sort: [], limit: nil, offset: nil, filter: %Expr.Call{}} = query
    end

    test "raises for a part that can't be unset" do
      assert_raise ArgumentError, ~r/can't unset :resource/, fn ->
        ArticleLive |> Query.new() |> Query.unset([:resource])
      end
    end
  end

  describe "key/1" do
    test "is equal for queries that only differ in their context" do
      query = ArticleLive |> Query.new(%{assigns: %{a: 1}}) |> Query.limit(1)

      assert Query.key(query) == Query.key(%{query | context: %{assigns: %{a: 2}}})
      refute Query.key(query) == query |> Query.limit(2) |> Query.key()
    end
  end
end
