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

  describe "compute/3" do
    test "checks the fields of a value that is a field or a path" do
      assert ArticleLive |> Query.new() |> Query.compute(:author_name, expr(author.name)) |> Map.fetch!(:computed) ==
               %{author_name: Expr.ref([:author], :name)}

      assert_raise ArgumentError, ~r/unknown field :unknown/, fn ->
        ArticleLive |> Query.new() |> Query.compute(:unknown, expr(unknown))
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

  describe "apply_to/2" do
    @items [
      %{id: 1, title: "Elixir", likes: 3, published: ~D[2026-01-02], author: %{name: "Ann"}, tags: [%{name: "fp"}]},
      %{id: 2, title: "erlang", likes: nil, published: ~D[2025-12-31], author: nil, tags: []},
      %{id: 3, title: "Gleam", likes: 5, published: nil, author: %{name: "Bob"}, tags: [%{name: "fp"}, %{name: "new"}]}
    ]

    defp ids(query), do: query |> Query.apply_to(@items) |> Enum.map(& &1.id)

    defp filtered(expression), do: ids(%{Query.new(ArticleLive) | filter: expression})

    test "keeps the items whose expression is true, with the nil rules of SQL" do
      assert filtered(expr(likes > 2)) == [1, 3]
      assert filtered(expr(not (likes > 4))) == [1]
      assert filtered(expr(is_nil(likes) or likes == 5)) == [2, 3]
      assert filtered(expr(likes in [3, 5])) == [1, 3]
      # As in SQL, a value not in a list with nil is unknown, so the negation keeps it neither.
      assert filtered(expr(likes in [5, nil])) == [3]
      assert filtered(expr(likes not in [5, nil])) == []
      assert filtered(expr(published < ^~D[2026-01-01])) == [2]
    end

    test "compares parts of strings, with or without the case" do
      assert filtered(expr(starts_with(title, "E"))) == [1]
      assert filtered(expr(starts_with(title, "E", ignore_case: true))) == [1, 2]
      assert filtered(expr(contains(title, "LEA", ignore_case: true))) == [3]
      assert filtered(expr(ends_with(title, "ang"))) == [2]
    end

    test "reads paths and exists from the loaded relationships" do
      assert filtered(expr(author.name == "Bob")) == [3]
      assert filtered(expr(exists(tags, name == "new"))) == [3]
      assert filtered(expr(not exists(tags, name == "fp"))) == [2]
    end

    test "searches every target for the term, ignoring the case and casting values to text" do
      query = ArticleLive |> Query.new() |> Query.search("e", [:title])
      assert ids(query) == [1, 2, 3]

      assert ArticleLive |> Query.new() |> Query.search("BO", ["author.name"]) |> ids() == [3]
      assert ArticleLive |> Query.new() |> Query.search("5", [:likes, :title]) |> ids() == [3]
      assert ArticleLive |> Query.new() |> Query.search("fp", [:tags]) |> ids() == [1, 3]
    end

    test "sorts with the nil rules of PostgreSQL, then skips and limits" do
      sorted = fn sorts -> ArticleLive |> Query.new() |> Query.sort(sorts) |> ids() end

      assert sorted.(likes: :asc) == [1, 3, 2]
      assert sorted.(likes: :desc) == [2, 3, 1]
      assert sorted.(likes: :asc_nulls_first) == [2, 1, 3]
      assert sorted.(likes: :desc_nulls_last) == [3, 1, 2]
      assert sorted.(published: :desc_nulls_last) == [1, 2, 3]

      assert ArticleLive |> Query.new() |> Query.sort(id: :desc) |> Query.offset(1) |> Query.limit(1) |> ids() == [2]
    end

    test "computes values before it filters, searches and sorts by them" do
      query =
        ArticleLive
        |> Query.new()
        |> Query.compute(:label, expr(concat([title, author.name], " by ")))
        |> Query.compute(:liked, expr(likes > 2))
        |> Query.search("ann", [:label])
        |> Query.sort(label: :desc)

      assert [%{id: 1, label: "Elixir by Ann", liked: true}] = Query.apply_to(query, @items)

      assert %{id: 2, label: "erlang", liked: nil} =
               query |> Query.unset([:search]) |> Query.apply_to(@items) |> List.first()
    end

    test "computes aggregates of the loaded related items" do
      # The schema of `ArticleLive` has no tags, so the values are not cast.
      computed = %{
        tag_count: Expr.aggregate(:count, :tags),
        fp_count: Expr.aggregate(:count, :tags, where: expr(name == "fp")),
        last_tag: Expr.aggregate(:first, :tags, value: expr(name), sort: [name: :desc])
      }

      query = ArticleLive |> Query.new() |> Map.put(:computed, computed) |> Query.sort(id: :asc)

      assert [
               %{tag_count: 1, fp_count: 1, last_tag: "fp"},
               %{tag_count: 0, fp_count: 0, last_tag: nil},
               %{tag_count: 2, fp_count: 1, last_tag: "new"}
             ] = Query.apply_to(query, @items)
    end

    test "computes with numbers, datetimes and strings, with the nil rules of SQL" do
      computed = %{
        double: expr(likes * 2),
        half: expr(likes / 2),
        sum: expr(likes - 1 + 10),
        ratio: expr(likes / ^2.0),
        minutes: expr(datetime_diff(^~U[2026-01-01 10:30:59Z], ^~U[2026-01-01 08:00:00Z], :minute)),
        text: expr(to_string(likes))
      }

      query = ArticleLive |> Query.new() |> Map.put(:computed, computed) |> Query.sort(id: :asc)

      assert [
               %{double: 6, half: 1, sum: 12, ratio: 1.5, minutes: 150, text: "3"},
               %{double: nil, half: nil, sum: nil, ratio: nil, minutes: 150, text: nil},
               %{double: 10, half: 2, sum: 14, text: "5"}
             ] = Query.apply_to(query, @items)
    end

    test "compares the values of expressions" do
      assert filtered(expr(likes * 2 > 7)) == [3]
      assert filtered(expr(to_string(likes) == "3")) == [1]
      assert filtered(expr(likes - 3 == id - 1)) == [1, 3]
    end

    test "raises for a native expression" do
      query = %{Query.new(ArticleLive) | filter: Expr.native(Backpex.Adapters.Ecto, :fragment)}

      assert_raise ArgumentError, ~r/can't apply the native expression/, fn -> Query.apply_to(query, @items) end
    end
  end

  describe "aggregate_items/2" do
    test "computes the aggregates with the nil rules of SQL" do
      query =
        ArticleLive
        |> Query.new()
        |> Query.aggregate(:total, :count)
        |> Query.aggregate(:with_likes, {:count, :likes})
        |> Query.aggregate(:sum, {:sum, :likes})
        |> Query.aggregate(:avg, {:avg, :likes})
        |> Query.aggregate(:min, {:min, :likes})
        |> Query.aggregate(:max, {:max, :likes}, where: expr(likes < 5))
        |> Query.aggregate(:none, {:sum, :likes}, where: expr(likes > 100))

      items = [%{likes: 3}, %{likes: nil}, %{likes: 5}]

      assert Query.aggregate_items(query, items) == %{
               total: 3,
               with_likes: 2,
               sum: 8,
               avg: 4.0,
               min: 3,
               max: 3,
               none: nil
             }
    end

    test "aggregates the values of expressions" do
      query =
        ArticleLive
        |> Query.new()
        |> Query.aggregate(:double, {:sum, expr(likes * 2)})
        |> Query.aggregate(:with_likes, {:count, expr(likes + 1)})
        |> Query.aggregate(:min, {:min, expr(likes - 1)})

      assert Query.aggregate_items(query, [%{likes: 3}, %{likes: nil}, %{likes: 5}]) ==
               %{double: 16, with_likes: 2, min: 2}
    end

    test "adds decimals with Decimal" do
      query =
        ArticleLive |> Query.new() |> Query.aggregate(:sum, {:sum, :price}) |> Query.aggregate(:max, {:max, :price})

      items = [%{price: Decimal.new("1.50")}, %{price: Decimal.new("2.25")}]

      assert %{sum: sum, max: max} = Query.aggregate_items(query, items)
      assert Decimal.equal?(sum, "3.75")
      assert Decimal.equal?(max, "2.25")
    end
  end
end
