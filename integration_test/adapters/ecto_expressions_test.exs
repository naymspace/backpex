defmodule Backpex.Integration.Adapters.EctoExpressionsTest do
  use Backpex.DataCase, async: true

  import Backpex.Expr, only: [expr: 1]

  alias Backpex.Adapters.Ecto, as: EctoAdapter
  alias Backpex.Test.Post
  alias Backpex.Test.PostLive
  alias Backpex.Test.User
  alias Backpex.Test.UserLive

  setup do
    ann = insert(:user, username: "ann", first_name: "Ann", last_name: "Ann")
    bob = insert(:user, username: "bob", first_name: "Bob", last_name: "Brown", age: nil)
    elixir = insert(:tag, name: "elixir")
    rust = insert(:tag, name: "rust")
    news = insert(:category, name: "News")

    insert(:post, title: "100% Elixir", likes: 200, user: ann, category: news, tags: [elixir])
    insert(:post, title: "Rust_Notes", likes: 5, user: bob, tags: [rust])
    insert(:post, title: "No author", likes: 50, user: nil, tags: [])

    %{news: news, elixir: elixir}
  end

  describe "comparisons" do
    test "compare a field to a value cast to the type of the field" do
      assert titles(expr(likes > 10)) == ["100% Elixir", "No author"]
      assert titles(expr(likes >= ^"50")) == ["100% Elixir", "No author"]
      assert titles(expr(10 > likes)) == ["Rust_Notes"]
      assert titles(expr(title in ["Rust_Notes", "Other"])) == ["Rust_Notes"]
    end

    test "compare a binary id to a string", %{news: news} do
      assert titles(expr(category_id == ^news.id)) == ["100% Elixir"]
      assert titles(expr(category_id in ^[news.id])) == ["100% Elixir"]
    end

    test "compare two fields" do
      assert usernames(expr(first_name == last_name)) == ["ann"]
    end

    test "keep items whose field is nil with is_nil, but not with a comparison or its negation" do
      assert usernames(expr(age == 30)) == ["ann"]
      assert usernames(expr(not (age == 30))) == []
      assert usernames(expr(age != 30 or is_nil(age))) == ["bob"]
    end

    test "take keyword lists as fields that equal values" do
      assert titles(likes: 5) == ["Rust_Notes"]
    end
  end

  describe "strings" do
    test "match a part of a string, also ignoring the case" do
      assert titles(expr(contains(title, "Elixir"))) == ["100% Elixir"]
      assert titles(expr(contains(title, "elixir"))) == []
      assert titles(expr(contains(title, "elixir", ignore_case: true))) == ["100% Elixir"]
      assert titles(expr(starts_with(title, "Rust"))) == ["Rust_Notes"]
      assert titles(expr(ends_with(title, "author"))) == ["No author"]
    end

    test "match % and _ literally" do
      assert titles(expr(contains(title, "%"))) == ["100% Elixir"]
      assert titles(expr(contains(title, "_"))) == ["Rust_Notes"]
    end
  end

  describe "paths" do
    test "compare a field of a related item" do
      assert titles(expr(user.username == "ann")) == ["100% Elixir"]
      assert titles(expr(category.name == "News")) == ["100% Elixir"]
    end

    test "keep items without the related item neither by a comparison nor by its negation" do
      assert titles(expr(not (user.username == "ann"))) == ["Rust_Notes"]
    end

    test "join a path once for every expression that uses it" do
      query =
        filter_query(PostLive, [
          expr(user.username == "ann"),
          expr(user.age == 30 or user.first_name == "Ann")
        ])

      assert [%{as: :backpex_user}] = query.joins
      assert [%Post{title: "100% Elixir"}] = Repo.all(query)
    end

    test "refuse a relationship to many items" do
      assert_raise ArgumentError, ~r/:tags to be a relationship to one item.*use exists\(tags, \.\.\.\)/, fn ->
        titles(expr(tags.name == "elixir"))
      end
    end
  end

  describe "exists" do
    test "keep items with a matching related item, without duplicating items" do
      assert titles(expr(exists(tags, name in ["elixir", "rust"]))) == ["100% Elixir", "Rust_Notes"]
      assert titles(expr(not exists(tags, name == "elixir"))) == ["No author", "Rust_Notes"]
    end

    test "go through several relationships and through associations" do
      address = insert(:address, city: "Hamburg")
      ann = Repo.get_by!(User, username: "ann")
      Repo.insert!(%Backpex.Test.UsersAddresses{user_id: ann.id, address_id: address.id, type: :shipping})

      assert usernames(expr(exists(posts.tags, name == "rust"))) == ["bob"]
      assert usernames(expr(exists(posts, exists(tags, name == "elixir")))) == ["ann"]
      assert usernames(expr(exists(addresses, city == "Hamburg"))) == ["ann"]
    end

    test "combine with paths" do
      assert titles(expr(user.username == "ann" and exists(tags, name == "elixir"))) == ["100% Elixir"]
    end
  end

  describe "native expressions" do
    test "are placed as they are" do
      native = Backpex.Expr.native(EctoAdapter, dynamic([post], fragment("lower(?)", post.title) == "rust_notes"))

      assert titles(native) == ["Rust_Notes"]
      assert expr(likes > 100) |> then(&Backpex.Expr.any([&1, native])) |> titles() == ["100% Elixir", "Rust_Notes"]
    end

    test "of another adapter are refused" do
      assert_raise ArgumentError, ~r/expected a native expression of Backpex.Adapters.Ecto/, fn ->
        titles(Backpex.Expr.native(SomeAdapter, :anything))
      end
    end
  end

  describe "with the LiveResource" do
    test "casts the values to the types of the fields of its description" do
      assert titles(expr(likes > "100")) == ["100% Elixir"]
      assert titles(expr(user.role == "user" and user.age == "30")) == ["100% Elixir"]
    end

    test "raises for unknown fields and paths through relationships to many items" do
      assert_raise ArgumentError, ~r/unknown field :unknown/, fn -> titles(expr(unknown == 1)) end

      assert_raise ArgumentError, ~r/:tags to be a relationship to one item/, fn ->
        titles(expr(tags.name == "elixir"))
      end
    end

    test "describes the resource and related items" do
      assert %{fields: %{likes: %{primitive: :integer}}, relationships: %{user: %{owner_key: :user_id}}} =
               Backpex.Resource.describe(PostLive)

      assert %{fields: %{role: %{primitive: :string}}} = Backpex.Resource.describe([:user], PostLive)
      assert Backpex.Resource.field_type(:likes, PostLive) == :integer
      assert %{cardinality: :many, through: []} = Backpex.Resource.association(:tags, PostLive)
    end
  end

  defp titles(expression) do
    PostLive |> filter_query([expression]) |> Repo.all() |> Enum.map(& &1.title) |> Enum.sort()
  end

  defp usernames(expression) do
    UserLive |> filter_query([expression]) |> Repo.all() |> Enum.map(& &1.username) |> Enum.sort()
  end

  defp filter_query(live_resource, expressions) do
    live_resource
    |> Backpex.Query.new()
    |> then(&Enum.reduce(expressions, &1, fn expression, query -> Backpex.Query.filter(query, expression) end))
    |> EctoAdapter.ecto_query()
  end
end
