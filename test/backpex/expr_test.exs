defmodule Backpex.ExprTest do
  use ExUnit.Case, async: true

  import Backpex.Expr

  alias Backpex.Adapter.Description
  alias Backpex.Expr
  alias Backpex.Expr.Call
  alias Backpex.Expr.Exists
  alias Backpex.Expr.Ref

  doctest Backpex.Expr

  describe "expr/1" do
    test "turns names into refs and literals and pinned values into values" do
      min = 10

      assert expr(likes >= ^min) == %Call{name: :>=, args: [%Ref{name: :likes}, 10]}
      assert expr(status == :draft) == %Call{name: :==, args: [%Ref{name: :status}, :draft]}
      assert expr(published == true) == %Call{name: :==, args: [%Ref{name: :published}, true]}
      assert expr(title != nil) == %Call{name: :!=, args: [%Ref{name: :title}, nil]}
      assert expr(id in [1, ^min]) == %Call{name: :in, args: [%Ref{name: :id}, [1, 10]]}
      assert expr(first_name == last_name) == %Call{name: :==, args: [%Ref{name: :first_name}, %Ref{name: :last_name}]}
    end

    test "turns dotted names into refs with a path" do
      assert expr(author.company.name == "Acme") ==
               %Call{name: :==, args: [%Ref{path: [:author, :company], name: :name}, "Acme"]}
    end

    test "refers to fields whose names are in variables" do
      field = :likes
      path = [:author]

      assert expr(ref(^field) > 1) == %Call{name: :>, args: [%Ref{name: :likes}, 1]}
      assert expr(ref(^path, ^field) > 1) == %Call{name: :>, args: [%Ref{path: [:author], name: :likes}, 1]}
      assert expr(ref(:likes) > 1) == %Call{name: :>, args: [%Ref{name: :likes}, 1]}
    end

    test "flattens and and or" do
      assert %Call{name: :and, args: [_a, _b, _c]} = expr(a == 1 and b == 2 and c == 3)
      assert %Call{name: :or, args: [_a, %Call{name: :and}]} = expr(a == 1 or (b == 2 and c == 3))
    end

    test "builds not, is_nil and the string functions" do
      assert expr(not is_nil(title)) == %Call{name: :not, args: [%Call{name: :is_nil, args: [%Ref{name: :title}]}]}

      assert expr(contains(title, "x", ignore_case: true)) ==
               %Call{name: :contains, args: [%Ref{name: :title}, "x"], opts: [ignore_case: true]}

      assert %Call{name: :starts_with, opts: []} = expr(starts_with(title, "x"))
      assert %Call{name: :ends_with, opts: []} = expr(ends_with(title, "x"))
    end

    test "builds exists with fields of the related items" do
      assert expr(exists(comments.author, active == true)) == %Exists{
               path: [:comments, :author],
               where: %Call{name: :==, args: [%Ref{name: :active}, true]}
             }
    end

    test "refuses unsupported expressions at compile time" do
      for {code, message} <- [
            {"expr(likes + 1 > 2)", ~r/unsupported expression: likes \+ 1/},
            {"expr(lower(title) == \"a\")", ~r/unsupported expression: lower\(title\)/},
            {"expr(exists(^path, a == 1))", ~r/expected a relationship such as tags/},
            {"expr(contains(title, \"a\", ^opts))", ~r/expected the options of contains\/3 to be a keyword list/}
          ] do
        assert_raise CompileError, message, fn ->
          Code.eval_string("import Backpex.Expr; " <> code)
        end
      end
    end
  end

  describe "all/1 and any/1" do
    test "ignore nil and take keyword lists" do
      assert Expr.all([]) == nil
      assert Expr.any([nil, nil]) == nil
      assert Expr.all([nil, [likes: 1]]) == %Call{name: :==, args: [%Ref{name: :likes}, 1]}

      assert Expr.all([expr(a == 1), expr(b == 2)]) == %Call{name: :and, args: [expr(a == 1), expr(b == 2)]}
    end
  end

  describe "cast/2" do
    @descriptions %{
      [] => %Description{
        fields: %{
          likes: %{type: :integer, primitive: :integer},
          title: %{type: :string, primitive: :string},
          role: %{type: Ecto.ParameterizedType.init(Ecto.Enum, values: [:user, :admin]), primitive: :string}
        },
        relationships: %{
          author: %{field: :author, cardinality: :one, owner_key: :author_id, through: []},
          tags: %{field: :tags, cardinality: :many, owner_key: :id, through: []}
        }
      },
      [:author] => %Description{fields: %{age: %{type: :integer, primitive: :integer}}},
      [:tags] => %Description{
        fields: %{name: %{type: :string, primitive: :string}, uses: %{type: :integer, primitive: :integer}}
      }
    }

    defp cast(expression), do: Expr.cast(expression, &Map.get(@descriptions, &1))

    test "casts the values compared to a field to the type of the field" do
      assert cast(expr(likes >= "10")) == expr(likes >= 10)
      assert cast(expr("10" < likes)) == expr(10 < likes)
      assert cast(expr(role == "admin")) == expr(role == :admin)
      assert cast(expr(likes in ["1", "2"])) == expr(likes in [1, 2])
      assert cast(expr(author.age == "30")) == expr(author.age == 30)
      assert cast(expr(exists(tags, uses > "1"))) == expr(exists(tags, uses > 1))
      assert cast(likes: "5") == expr(likes == 5)
    end

    test "keeps values that can't be cast, nil, empty strings and parts of strings" do
      assert cast(expr(likes >= 2.5)) == expr(likes >= 2.5)
      assert cast(expr(likes == nil)) == expr(likes == nil)
      assert cast(expr(title == "")) == expr(title == "")
      assert cast(expr(contains(title, 1))) == expr(contains(title, 1))
    end

    test "checks the fields of comparisons, is_nil and the string functions and keeps native expressions" do
      native = Expr.native(SomeAdapter, :anything)

      assert cast(expr((is_nil(title) and contains(title, "a")) or title != role)) ==
               expr((is_nil(title) and contains(title, "a")) or title != role)

      assert cast(Expr.any([native, expr(likes > 1)])) == Expr.any([native, expr(likes > 1)])
      assert cast(nil) == nil
    end

    test "raises for unknown fields and relationships and for paths through relationships to many items" do
      assert_raise ArgumentError, ~r/unknown field :unknown in \[\]/, fn -> cast(expr(unknown == 1)) end
      assert_raise ArgumentError, ~r/unknown field :name in \[:author\]/, fn -> cast(expr(author.name == 1)) end
      assert_raise ArgumentError, ~r/unknown relationship :editor/, fn -> cast(expr(editor.age == 1)) end

      assert_raise ArgumentError, ~r/unknown relationship path \[:editor\]/, fn ->
        cast(expr(exists(editor, a == 1)))
      end

      assert_raise ArgumentError, ~r/unknown field :age in \[:tags\]/, fn -> cast(expr(exists(tags, age == 1))) end

      assert_raise ArgumentError, ~r/:tags to be a relationship to one item.*exists\(tags, \.\.\.\)/, fn ->
        cast(expr(tags.name == "elixir"))
      end
    end
  end

  describe "normalize/1" do
    test "keeps expressions and nil, and turns keyword lists into comparisons" do
      assert Expr.normalize(nil) == nil
      expression = expr(a == 1)

      assert Expr.normalize(expression) == expression
      assert Expr.normalize(a: 1, b: 2) == expr(a == 1 and b == 2)
    end

    test "refuses the condition tuples of earlier versions and other terms" do
      assert_raise ArgumentError, ~r/expected an expression such as expr\(published == true\)/, fn ->
        Expr.normalize({:==, :published, true})
      end

      assert_raise ArgumentError, ~r/keyword list of fields and values/, fn -> Expr.normalize([1, 2]) end
    end
  end
end
