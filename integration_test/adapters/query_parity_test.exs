defmodule Backpex.Integration.Adapters.QueryParityTest do
  @moduledoc """
  Runs the same queries through `Backpex.Adapters.Ecto` and through `Backpex.Query.apply_to/2` and
  `Backpex.Query.aggregate_items/2` on all rows, and expects the same items, counts and aggregates. So an adapter that
  leaves parts of a query to Backpex (see `c:Backpex.Adapter.supports?/2`) shows the items PostgreSQL would return.

  The strings of sorted and compared fields are ASCII in one case, as PostgreSQL orders strings by the collation of the
  database and Backpex by their code points, see `Backpex.Query.apply_to/2`.
  """
  use Backpex.DataCase, async: true

  import Backpex.Expr, only: [expr: 1]

  alias Backpex.Adapters.Ecto, as: EctoAdapter
  alias Backpex.Query
  alias Backpex.Test.OrderNullsDefaultUserLive, as: UserLive
  alias Backpex.Test.PostLive

  @counted [:sort, :default_sort, :limit, :offset, :load]
  @directions [:asc, :desc, :asc_nulls_first, :asc_nulls_last, :desc_nulls_first, :desc_nulls_last]

  setup do
    ann = insert(:user, username: "ann", first_name: "Ann", last_name: "Ann", age: 30, avatar: "a.png")
    bob = insert(:user, username: "bob", first_name: "Bob", last_name: "Brown", age: nil, avatar: nil)
    cy = insert(:user, username: "cy", first_name: "Cy", last_name: "Cole", age: 25, avatar: "c.png", role: :admin)
    insert(:user, username: "dee", first_name: "Dee", last_name: "Dee", age: 30, avatar: nil)

    elixir = insert(:tag, name: "elixir")
    rust = insert(:tag, name: "rust")
    percent = insert(:tag, name: "50%_off")
    news = insert(:category, name: "News")
    tech = insert(:category, name: "Tech")

    insert(:post, title: "100% Elixir", likes: 200, published: true, user: ann, category: news, tags: [elixir])
    insert(:post, title: "Rust_Notes", likes: 5, published: false, user: bob, category: nil, tags: [rust, elixir])
    insert(:post, title: "No author", likes: 50, published: true, user: nil, category: tech, tags: [])
    insert(:post, title: "elixir tips", likes: 7, published: false, user: cy, category: news, tags: [elixir, percent])
    insert(:post, title: "Zig", likes: 0, published: true, user: ann, category: nil, tags: [])

    %{ann: ann, news: news}
  end

  describe "read/1 and count/1" do
    test "keep the same posts for filters on fields", %{ann: ann, news: news} do
      assert_parity(PostLive, [
        expr(likes == 5),
        expr(likes != 5),
        expr(likes < 7),
        expr(likes <= 7),
        expr(likes > 7),
        expr(likes >= 7),
        expr(5 < likes),
        expr(likes > "7"),
        expr(published == true),
        expr(published != true),
        expr(not (likes > 7)),
        expr(likes > 5 and published == true),
        expr(likes > 100 or published == false),
        expr(not (likes > 100 or published == false)),
        expr(likes in [5, 200]),
        expr(likes not in [5, 200]),
        expr(title in ["Zig", "Other"]),
        expr(title in []),
        expr(title not in []),
        expr(is_nil(user_id)),
        expr(not is_nil(user_id)),
        expr(user_id == ^ann.id),
        expr(user_id != ^ann.id),
        expr(not (user_id == ^ann.id)),
        expr(user_id != ^ann.id or is_nil(user_id)),
        expr(user_id in ^[ann.id]),
        expr(user_id not in ^[ann.id]),
        expr(category_id == ^news.id),
        expr(category_id != ^news.id),
        expr(category_id in ^[news.id]),
        expr(is_nil(category_id) and is_nil(user_id)),
        expr(is_nil(category_id) or is_nil(user_id)),
        # Unknown and true, unknown or false: the three values of the logic of SQL.
        expr(user_id == ^ann.id and likes > 100),
        expr(not (user_id == ^ann.id and likes > 100)),
        expr(user_id == ^ann.id or likes < 10),
        expr(not (user_id == ^ann.id or likes < 10)),
        [published: true, likes: 200]
      ])
    end

    test "keep the same posts for parts of strings" do
      assert_parity(PostLive, [
        expr(contains(title, "Elixir")),
        expr(contains(title, "elixir")),
        expr(contains(title, "ELIXIR", ignore_case: true)),
        expr(not contains(title, "elixir", ignore_case: true)),
        expr(starts_with(title, "Rust")),
        expr(starts_with(title, "rust")),
        expr(starts_with(title, "rust", ignore_case: true)),
        expr(ends_with(title, "tips")),
        expr(ends_with(title, "NOTES", ignore_case: true)),
        expr(contains(title, "%")),
        expr(contains(title, "_")),
        expr(contains(title, "t_N")),
        expr(contains(title, "0% E")),
        expr(starts_with(title, "100%")),
        expr(starts_with(title, "%")),
        expr(ends_with(title, "_Notes")),
        expr(contains(title, "\\")),
        expr(contains(title, "")),
        expr(contains(title, " "))
      ])
    end

    test "keep the same posts for paths through a relationship to one item" do
      assert_parity(PostLive, [
        expr(user.username == "ann"),
        expr(user.username != "ann"),
        expr(not (user.username == "ann")),
        expr(user.username in ["ann", "cy"]),
        expr(user.age > 26),
        expr(not (user.age > 26)),
        expr(is_nil(user.age)),
        expr(not is_nil(user.age)),
        expr(is_nil(user.username)),
        expr(user.role == :admin),
        expr(category.name == "News"),
        expr(contains(category.name, "e", ignore_case: true)),
        expr(user.age == 30 or category.name == "Tech"),
        expr(not (user.age == 30 or category.name == "Tech")),
        expr(user.age == 30 and category.name == "News"),
        expr(not (user.age == 30 and category.name == "News")),
        expr(user.first_name == user.last_name)
      ])
    end

    test "keep the same items for exists over relationships to many items" do
      assert_parity(PostLive, [
        expr(exists(tags, name == "elixir")),
        expr(not exists(tags, name == "elixir")),
        expr(exists(tags, name in ["rust", "none"])),
        expr(exists(tags, contains(name, "%_"))),
        expr(exists(tags, is_nil(name))),
        expr(exists(tags, not is_nil(name))),
        expr(not exists(tags, not is_nil(name))),
        expr(user.username == "ann" and exists(tags, name == "elixir")),
        expr(user.username == "bob" or not exists(tags, name == "elixir"))
      ])

      assert_parity(UserLive, [
        expr(exists(posts, likes > 100)),
        expr(not exists(posts, likes > 100)),
        expr(not exists(posts, likes >= 0)),
        expr(exists(posts, is_nil(category_id))),
        expr(exists(posts.tags, name == "rust")),
        expr(exists(posts, exists(tags, name == "50%_off"))),
        expr(exists(posts, category.name == "News")),
        expr(exists(posts.category, name == "News")),
        expr(is_nil(age) and exists(posts, published == false))
      ])
    end

    test "keep the same users for filters on a field with nil" do
      assert_parity(UserLive, [
        expr(age == 30),
        expr(age != 30),
        expr(not (age == 30)),
        expr(age != 30 or is_nil(age)),
        expr(age < 30),
        expr(not (age < 30)),
        expr(age in [25, 30]),
        expr(age not in [25]),
        expr(is_nil(age)),
        expr(not is_nil(age)),
        expr(is_nil(avatar) and is_nil(age)),
        expr(age == 30 and is_nil(avatar)),
        expr(not (age == 30 and is_nil(avatar))),
        expr(first_name == last_name),
        expr(first_name != last_name),
        expr(role == :admin),
        expr(role != "admin"),
        expr(contains(avatar, "png")),
        expr(not contains(avatar, "a"))
      ])
    end

    test "keep the same items for a search" do
      assert_parity(PostLive, [
        search(PostLive, "elixir", [:title]),
        search(PostLive, "ELIXIR", [:title]),
        search(PostLive, " tips", [:title]),
        search(PostLive, "nothing", [:title]),
        search(PostLive, "ann", [:title, "user.username"]),
        search(PostLive, "o", [:title, "user.username", "category.name"]),
        search(PostLive, "5", [:likes]),
        search(PostLive, "20", [:likes, :title]),
        search(PostLive, "true", [:published]),
        search(PostLive, "anything", []),
        PostLive |> Query.new() |> Query.filter(expr(likes > 5)) |> Query.search("elixir", [:title])
      ])

      assert_parity(UserLive, [
        search(UserLive, "PNG", [:avatar]),
        search(UserLive, "3", [:age, :avatar]),
        search(UserLive, "admin", [:role])
      ])
    end

    test "return the same items in the same order for sorts, also with nil" do
      for direction <- @directions do
        assert_parity(UserLive, [
          sort(UserLive, age: direction, username: :asc),
          sort(UserLive, avatar: direction, username: :desc),
          sort(UserLive, age: direction, avatar: direction, username: :asc)
        ])

        assert_parity(PostLive, [
          sort(PostLive, likes: direction),
          sort(PostLive, [{"user.age", direction}, {:likes, :asc}]),
          sort(PostLive, [{"user.username", direction}, {:likes, :desc}]),
          sort(PostLive, [{"category.name", direction}, {"user.age", direction}, {:likes, :asc}]),
          sort(PostLive, published: direction, likes: :asc),
          sort(PostLive, user_id: direction, likes: :asc)
        ])
      end

      assert_parity(PostLive, [PostLive |> Query.new() |> Query.default_sort(likes: :desc)])
    end

    test "return the same page for an offset and a limit" do
      sorted = sort(PostLive, likes: :asc)

      assert_parity(PostLive, [
        Query.limit(sorted, 2),
        Query.offset(sorted, 2),
        sorted |> Query.offset(1) |> Query.limit(2),
        sorted |> Query.offset(4) |> Query.limit(2),
        sorted |> Query.offset(9) |> Query.limit(2),
        Query.limit(sorted, 0),
        sorted
        |> Query.filter(expr(exists(tags, name == "elixir") or user.age == 30))
        |> Query.search("i", [:title, "user.username"])
        |> Query.offset(1)
        |> Query.limit(1)
      ])
    end
  end

  describe "aggregate/1" do
    test "returns the same values for every kind of aggregate" do
      posts =
        PostLive
        |> Query.new()
        |> Query.aggregate(:count, :count)
        |> Query.aggregate(:count_user, {:count, :user_id})
        |> Query.aggregate(:sum, {:sum, :likes})
        |> Query.aggregate(:min, {:min, :likes})
        |> Query.aggregate(:max, {:max, :likes})
        |> Query.aggregate(:published, :count, where: expr(published == true))
        |> Query.aggregate(:likes_of_ann, {:sum, :likes}, where: expr(user.username == "ann"))
        |> Query.aggregate(:max_tagged, {:max, :likes}, where: expr(exists(tags, name == "elixir")))
        |> Query.aggregate(:none, {:sum, :likes}, where: expr(likes > 1000))
        |> Query.aggregate(:count_none, :count, where: expr(likes > 1000))
        |> Query.aggregate(:min_none, {:min, :likes}, where: expr(likes > 1000))

      users =
        UserLive
        |> Query.new()
        |> Query.aggregate(:count, :count)
        |> Query.aggregate(:count_age, {:count, :age})
        |> Query.aggregate(:sum, {:sum, :age})
        |> Query.aggregate(:min, {:min, :age})
        |> Query.aggregate(:max, {:max, :age})
        |> Query.aggregate(:min_username, {:min, :username})
        |> Query.aggregate(:max_username, {:max, :username})
        |> Query.aggregate(:sum_nil, {:sum, :age}, where: expr(is_nil(age)))
        |> Query.aggregate(:count_nil, {:count, :age}, where: expr(is_nil(age)))

      assert_aggregate_parity([
        posts,
        Query.filter(posts, expr(likes < 100)),
        Query.filter(posts, expr(likes > 1000)),
        Query.search(posts, "elixir", [:title]),
        posts |> Query.filter(expr(user.age == 30)) |> Query.search("i", [:title]),
        users,
        Query.filter(users, expr(exists(posts, likes > 1))),
        Query.filter(users, expr(is_nil(age)))
      ])
    end

    test "returns the same average" do
      posts = PostLive |> Query.new() |> Query.aggregate(:avg, {:avg, :likes})
      users = UserLive |> Query.new() |> Query.aggregate(:avg, {:avg, :age})

      for query <- [posts, users, Query.filter(posts, expr(likes > 1000)), Query.filter(users, expr(is_nil(age)))] do
        {:ok, %{avg: ecto}} = EctoAdapter.aggregate(query)
        %{avg: memory} = Query.aggregate_items(query, in_memory(query))

        assert number(ecto) == number(memory)
      end
    end
  end

  # The queries below differ between the Ecto adapter and Backpex in memory. Each test is skipped with the difference
  # as its reason, and passes once both agree. Run them with `mix test --include skip`.
  describe "known differences" do
    @tag skip: "the Ecto adapter takes % and _ in a search term as wildcards of ILIKE, in memory they are literal"
    test "a search for % or _ keeps the same posts" do
      assert_parity(PostLive, [
        search(PostLive, "%", [:title]),
        search(PostLive, "_", [:title]),
        search(PostLive, "t_N", [:title])
      ])
    end

    @tag skip: "PostgreSQL orders strings by the collation of the database, Backpex in memory by their code points"
    test "strings in both cases sort and compare the same" do
      names = PostLive |> Query.new() |> Query.aggregate(:min, {:min, :title}) |> Query.aggregate(:max, {:max, :title})

      assert_parity(PostLive, [sort(PostLive, title: :asc), expr(title > "a")])
      assert_aggregate_parity([names])
    end

    @tag skip: "PostgreSQL returns the average of integers as a decimal, Backpex in memory as a float"
    test "the average of integers has the same type" do
      assert_aggregate_parity([PostLive |> Query.new() |> Query.aggregate(:avg, {:avg, :likes})])
    end
  end

  defp search(live_resource, term, targets), do: live_resource |> Query.new() |> Query.search(term, targets)
  defp sort(live_resource, sorts), do: live_resource |> Query.new() |> Query.sort(sorts)

  defp number(nil), do: nil
  defp number(%Decimal{} = value), do: value |> Decimal.to_float() |> Float.round(6)
  defp number(value), do: Float.round(value / 1, 6)

  # Reads and counts every query with the Ecto adapter and in memory. Takes queries or expressions to filter by, and
  # fails with every query whose results differ.
  defp assert_parity(live_resource, queries) do
    differences =
      for query <- queries, query = to_query(live_resource, query), difference <- differences(query) do
        difference
      end

    assert differences == []
  end

  defp to_query(_live_resource, %Query{} = query), do: query
  defp to_query(live_resource, expression), do: live_resource |> Query.new() |> Query.filter(expression)

  defp differences(query) do
    counted = Query.unset(query, @counted)

    {:ok, ecto_items} = EctoAdapter.read(query)
    {:ok, ecto_count} = EctoAdapter.count(counted)

    memory_items = in_memory(query)

    [
      {:read, keys(query, ecto_items), keys(query, memory_items)},
      {:count, ecto_count, counted |> in_memory() |> length()}
    ]
    |> Enum.reject(fn {_function, ecto, memory} -> ecto == memory end)
    |> Enum.map(fn {function, ecto, memory} -> %{function => describe(query), ecto: ecto, memory: memory} end)
  end

  defp assert_aggregate_parity(queries) do
    differences =
      for query <- queries,
          {:ok, ecto} = EctoAdapter.aggregate(query),
          memory = Query.aggregate_items(query, in_memory(query)),
          ecto != memory do
        %{aggregate: describe(query), ecto: ecto, memory: memory}
      end

    assert differences == []
  end

  # Applies the query to all rows in memory, which the Ecto adapter reads with every relationship the queries use.
  defp in_memory(%Query{resource: live_resource} = query) do
    load = if live_resource == PostLive, do: [:user, :category, :tags], else: [posts: [:tags, :category]]
    {:ok, rows} = live_resource |> Query.new() |> Query.load(load) |> EctoAdapter.read()

    Query.apply_to(query, rows)
  end

  # The names of the items, in their order if the query sorts them.
  defp keys(%Query{resource: live_resource} = query, items) do
    name = if live_resource == PostLive, do: :title, else: :username
    names = Enum.map(items, &Map.fetch!(&1, name))

    if Query.sorts(query) == [], do: Enum.sort(names), else: names
  end

  defp describe(query), do: Map.take(query, [:filter, :search, :sort, :default_sort, :offset, :limit])
end
