defmodule Backpex.Adapters.Ecto.WhereTest do
  # Not async: the test counts the atoms of the VM, which tests that run at the same time create, too.
  use ExUnit.Case, async: false

  import Backpex.Expr, only: [expr: 1]

  alias Backpex.Adapters.Ecto.Where
  alias Backpex.Expr

  defmodule Comment do
    use Ecto.Schema

    schema "comments" do
      field :likes, :integer
      belongs_to :post, Backpex.Adapters.Ecto.WhereTest.Post
    end
  end

  defmodule Post do
    use Ecto.Schema

    schema "posts" do
      field :title, :string
      has_many :comments, Backpex.Adapters.Ecto.WhereTest.Comment
    end
  end

  test "names the joins and the values of aggregates without new atoms for their values" do
    build = fn likes ->
      liked = Expr.aggregate(:count, :comments, where: expr(likes > ^likes))
      most_likes = Expr.aggregate(:max, :comments, value: expr(likes + ^likes), where: expr(likes > ^likes))

      {query, joined} = Where.join_aggregates(Post, [liked, most_likes])
      query = Where.where_expr(query, expr(^liked > ^likes and ^most_likes > 0), joined)
      {query, _sum} = Where.value(query, expr(^liked + ^most_likes), joined)

      query
    end

    names = fn query -> Enum.map(query.joins, & &1.as) end

    # The first run creates the atoms the code itself needs.
    assert 0 |> build.() |> names.() == [:backpex_aggregates_1, :backpex_aggregates_2]

    atoms = :erlang.system_info(:atom_count)
    queries = Enum.map(1..500, build)

    assert :erlang.system_info(:atom_count) == atoms
    assert queries |> Enum.map(names) |> Enum.uniq() == [[:backpex_aggregates_1, :backpex_aggregates_2]]
  end
end
