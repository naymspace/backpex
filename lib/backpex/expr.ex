defmodule Backpex.Expr do
  @moduledoc ~S"""
  Expressions that describe which items to keep, independent of the data source.

  Filters return an expression from `c:Backpex.Filter.condition/3`, metrics take one as their `:where` option, and the
  adapter of the LiveResource turns it into a query of its data source. Write expressions with `expr/1`:

      import Backpex.Expr

      expr(published == true)
      expr(likes >= ^min_likes and status != "done")
      expr(ref(^field) in ^values)
      expr(author.name == ^name)
      expr(exists(tags, name == "elixir"))
      expr(contains(title, ^search, ignore_case: true))

  Inside `expr/1`, a name without `^` refers to a field of the items, e.g. a column of the `Ecto.Schema` of the
  resource. `^` takes the value of an Elixir expression, so `^min_likes` is a value, and so are literals such as `true`,
  `"done"` or `:draft`. `ref(^field)` refers to the field whose name is in a variable, e.g. in a filter that works for
  any field.

  ## Operators and functions

    * `==`, `!=`, `<`, `<=`, `>`, `>=` - compare a field to a value or to another field.
    * `in` - keeps the items whose field has one of the values. The values must not contain `nil`, combine the
      expression with `is_nil(field)` in an `or` instead.
    * `is_nil(field)` - keeps the items whose field is `nil`. Use it instead of comparing a field to `nil`.
    * `contains(field, value)`, `starts_with(field, value)` and `ends_with(field, value)` - compare a string field to
      a part of a string. Pass `ignore_case: true` as the third argument to ignore the case.
    * `exists(relationship, expression)` - keeps the items with at least one related item that matches the expression.
      The fields in the expression are fields of the related items.
    * `and`, `or` and `not` - combine expressions.

  As in SQL, an item whose field is `nil` is kept neither by a comparison of this field nor by its negation, e.g.
  `expr(not (status == "done"))` doesn't keep items without a status. To keep them, write
  `expr(status != "done" or is_nil(status))`.

  ## Relationships

  A path such as `author.name` refers to a field of a related item. Paths go through relationships to one item only
  (e.g. `belongs_to` or `has_one`). For relationships to many items, use `exists/2`, which says whether any related item
  matches: `expr(exists(tags, name == "elixir"))`. A path in `exists/2` may go through several relationships, e.g.
  `exists(comments.author, active == true)`.

  ## Keyword lists

  Wherever Backpex takes an expression, a keyword list stands for fields that equal values, e.g. `[published: true]` is
  `expr(published == true)`. Use it for simple conditions such as the `:where` of a metric.

  ## Expressions of the adapter

  An expression that only the adapter can express, e.g. a fragment of SQL, is wrapped with `native/2`. The adapter
  takes it as it is, and other adapters refuse it:

      Backpex.Expr.native(Backpex.Adapters.Ecto, dynamic([post], fragment("lower(?)", post.title) == ^title))

  ## Building expressions

  `expr/1` returns the structs `Backpex.Expr.Ref`, `Backpex.Expr.Call`, `Backpex.Expr.Exists` and
  `Backpex.Expr.Native`. Adapters read these structs. To build expressions in code, use `ref/1`, `ref/2`, `all/1` and
  `any/1`, e.g. for a range with an optional start and end:

      Backpex.Expr.all([
        start && expr(ref(^field) >= ^start),
        stop && expr(ref(^field) <= ^stop)
      ])
  """

  defmodule Ref do
    @moduledoc """
    A field of the items, or of related items when `path` names the relationships to it, see `Backpex.Expr`.
    """

    @enforce_keys [:name]
    defstruct path: [], name: nil

    @type t :: %__MODULE__{path: [atom()], name: atom()}
  end

  defmodule Call do
    @moduledoc """
    An operator or a function applied to its arguments, see `Backpex.Expr`.

    `name` is one of `:==`, `:!=`, `:<`, `:<=`, `:>`, `:>=`, `:in`, `:is_nil`, `:contains`, `:starts_with`,
    `:ends_with`, `:and`, `:or` and `:not`. `opts` holds the options of a function, e.g. `ignore_case: true`.
    """

    @enforce_keys [:name, :args]
    defstruct name: nil, args: [], opts: []

    @type t :: %__MODULE__{name: atom(), args: [Backpex.Expr.t() | term()], opts: keyword()}
  end

  defmodule Exists do
    @moduledoc """
    Keeps the items with at least one related item, at the end of the relationships in `path`, that matches `where`,
    see `Backpex.Expr`.
    """

    @enforce_keys [:path, :where]
    defstruct path: [], where: nil

    @type t :: %__MODULE__{path: [atom(), ...], where: Backpex.Expr.t()}
  end

  defmodule Native do
    @moduledoc """
    An expression that only `adapter` understands, see `Backpex.Expr.native/2`.
    """

    @enforce_keys [:adapter, :expr]
    defstruct adapter: nil, expr: nil

    @type t :: %__MODULE__{adapter: module(), expr: term()}
  end

  @typedoc """
  An expression, see the module documentation.
  """
  @type t :: Ref.t() | Call.t() | Exists.t() | Native.t()

  @comparisons [:==, :!=, :<, :<=, :>, :>=]
  @string_functions [:contains, :starts_with, :ends_with]

  @doc """
  Builds an expression, see the module documentation.

  ## Examples

      iex> import Backpex.Expr
      iex> expr(likes >= 10)
      %Backpex.Expr.Call{name: :>=, args: [%Backpex.Expr.Ref{path: [], name: :likes}, 10]}

      iex> import Backpex.Expr
      iex> field = :status
      iex> expr(ref(^field) in ^["open", "pending"])
      %Backpex.Expr.Call{name: :in, args: [%Backpex.Expr.Ref{path: [], name: :status}, ["open", "pending"]]}

      iex> import Backpex.Expr
      iex> expr(exists(tags, name == "elixir"))
      %Backpex.Expr.Exists{
        path: [:tags],
        where: %Backpex.Expr.Call{name: :==, args: [%Backpex.Expr.Ref{path: [], name: :name}, "elixir"]}
      }
  """
  defmacro expr(expression), do: build(expression, __CALLER__)

  defp build({:^, _meta, [value]}, _caller), do: value

  defp build({operator, _meta, [left, right]}, caller) when operator in [:in | @comparisons] do
    call(operator, [build(left, caller), build(right, caller)])
  end

  defp build({operator, _meta, [_left, _right]} = expression, caller) when operator in [:and, :or] do
    args = expression |> flatten(operator) |> Enum.map(&build(&1, caller))

    call(operator, args)
  end

  defp build({:not, _meta, [expression]}, caller), do: call(:not, [build(expression, caller)])
  defp build({:is_nil, _meta, [field]}, caller), do: call(:is_nil, [build(field, caller)])

  defp build({function, _meta, [field, value]}, caller) when function in @string_functions do
    call(function, [build(field, caller), build(value, caller)])
  end

  defp build({function, meta, [field, value, opts]}, caller) when function in @string_functions do
    if not Keyword.keyword?(opts) do
      compile_error!(caller, meta, "expected the options of #{function}/3 to be a keyword list, got: #{show(opts)}")
    end

    quote do
      %Call{
        name: unquote(function),
        args: [unquote(build(field, caller)), unquote(build(value, caller))],
        opts: unquote(opts)
      }
    end
  end

  defp build({:exists, meta, [path, expression]}, caller) do
    case path(path) do
      {:ok, path} ->
        quote(do: %Exists{path: unquote(path), where: unquote(build(expression, caller))})

      :error ->
        compile_error!(caller, meta, "expected a relationship such as tags or comments.author, got: #{show(path)}")
    end
  end

  defp build({:ref, _meta, [name]}, caller), do: quote(do: Backpex.Expr.ref(unquote(build_name(name, caller))))

  defp build({:ref, _meta, [path, name]}, caller) do
    quote(do: Backpex.Expr.ref(unquote(build_name(path, caller)), unquote(build_name(name, caller))))
  end

  defp build({name, _meta, context}, _caller) when is_atom(name) and is_atom(context) do
    quote(do: %Ref{path: [], name: unquote(name)})
  end

  defp build({{:., _meta, [_left, field]}, dot_meta, []} = expression, caller) when is_atom(field) do
    case path(expression) do
      {:ok, path} ->
        {path, [name]} = Enum.split(path, -1)
        quote(do: %Ref{path: unquote(path), name: unquote(name)})

      :error ->
        compile_error!(caller, dot_meta, "expected a field such as author.name, got: #{show(expression)}")
    end
  end

  defp build(list, caller) when is_list(list), do: Enum.map(list, &build(&1, caller))

  defp build(literal, _caller) when is_number(literal) or is_binary(literal) or is_atom(literal), do: literal

  defp build({_name, meta, _args} = expression, caller) do
    compile_error!(caller, meta, "unsupported expression: #{show(expression)}. #{supported()}")
  end

  defp build(expression, caller), do: compile_error!(caller, [], "unsupported expression: #{show(expression)}")

  defp build_name({:^, _meta, [value]}, _caller), do: value
  defp build_name(name, _caller) when is_atom(name), do: name

  defp build_name(names, caller) when is_list(names) do
    if Enum.all?(names, &is_atom/1), do: names, else: compile_error!(caller, [], "expected atoms, got: #{show(names)}")
  end

  defp build_name(name, caller), do: compile_error!(caller, [], "expected ^name or an atom in ref, got: #{show(name)}")

  defp call(name, args), do: quote(do: %Call{name: unquote(name), args: unquote(args)})

  defp flatten({operator, _meta, [left, right]}, operator), do: flatten(left, operator) ++ flatten(right, operator)
  defp flatten(expression, _operator), do: [expression]

  # The names of a field or relationship such as `tags` or `comments.author`.
  defp path(expression), do: path(expression, [])

  defp path({name, _meta, context}, names) when is_atom(name) and is_atom(context), do: {:ok, [name | names]}
  defp path({{:., _meta, [left, name]}, _dot_meta, []}, names) when is_atom(name), do: path(left, [name | names])
  defp path(_expression, _names), do: :error

  defp supported do
    "Expressions support ==, !=, <, <=, >, >=, in, and, or, not, is_nil/1, contains/2, starts_with/2, ends_with/2, " <>
      "exists/2, ref/1 and ref/2, see Backpex.Expr"
  end

  defp show(expression), do: Macro.to_string(expression)

  defp compile_error!(caller, meta, description) do
    raise CompileError, file: caller.file, line: Keyword.get(meta, :line, caller.line), description: description
  end

  @doc """
  Returns a reference to the field `name` of the items.

      iex> Backpex.Expr.ref(:likes)
      %Backpex.Expr.Ref{path: [], name: :likes}
  """
  @spec ref(atom()) :: Ref.t()
  def ref(name) when is_atom(name), do: %Ref{path: [], name: name}

  @doc """
  Returns a reference to the field `name` of the related items at the end of `path`, see the
  [Relationships](#module-relationships) section.

      iex> Backpex.Expr.ref([:author], :name)
      %Backpex.Expr.Ref{path: [:author], name: :name}
  """
  @spec ref([atom()], atom()) :: Ref.t()
  def ref(path, name) when is_list(path) and is_atom(name), do: %Ref{path: path, name: name}

  @doc """
  Combines the expressions with `and`. Ignores `nil`, and returns `nil` (all items) if no expression is left.

      iex> Backpex.Expr.all([nil, Backpex.Expr.expr(likes > 1)])
      %Backpex.Expr.Call{name: :>, args: [%Backpex.Expr.Ref{path: [], name: :likes}, 1]}

      iex> Backpex.Expr.all([nil])
      nil
  """
  @spec all([t() | keyword() | nil]) :: t() | nil
  def all(expressions) when is_list(expressions), do: combine(:and, expressions)

  @doc """
  Combines the expressions with `or`. Ignores `nil`, and returns `nil` (all items) if no expression is left.

      iex> Backpex.Expr.any([Backpex.Expr.expr(published == true), Backpex.Expr.expr(featured == true)])
      %Backpex.Expr.Call{
        name: :or,
        args: [
          %Backpex.Expr.Call{name: :==, args: [%Backpex.Expr.Ref{path: [], name: :published}, true]},
          %Backpex.Expr.Call{name: :==, args: [%Backpex.Expr.Ref{path: [], name: :featured}, true]}
        ]
      }
  """
  @spec any([t() | keyword() | nil]) :: t() | nil
  def any(expressions) when is_list(expressions), do: combine(:or, expressions)

  defp combine(operator, expressions) do
    expressions = expressions |> Enum.map(&normalize/1) |> Enum.reject(&is_nil/1)

    case expressions do
      [] -> nil
      [expression] -> expression
      expressions -> %Call{name: operator, args: expressions}
    end
  end

  @doc """
  Wraps an expression that only `adapter` understands, see the
  [Expressions of the adapter](#module-expressions-of-the-adapter) section.
  """
  @spec native(module(), term()) :: Native.t()
  def native(adapter, expression) when is_atom(adapter), do: %Native{adapter: adapter, expr: expression}

  @doc """
  Returns the expression for an expression, a keyword list of fields and values, or `nil`. Raises for anything else,
  e.g. for the condition tuples of earlier versions.

  Adapters call it on every expression they receive.

      iex> Backpex.Expr.normalize(published: true)
      %Backpex.Expr.Call{name: :==, args: [%Backpex.Expr.Ref{path: [], name: :published}, true]}

      iex> Backpex.Expr.normalize([])
      nil
  """
  @spec normalize(t() | keyword() | nil) :: t() | nil
  def normalize(nil), do: nil
  def normalize(%struct{} = expression) when struct in [Ref, Call, Exists, Native], do: expression

  def normalize(keyword) when is_list(keyword) do
    if Keyword.keyword?(keyword) do
      all(Enum.map(keyword, fn {name, value} -> %Call{name: :==, args: [ref(name), value]} end))
    else
      raise ArgumentError, "expected an expression or a keyword list of fields and values, got: #{inspect(keyword)}"
    end
  end

  def normalize(expression) do
    raise ArgumentError, """
    expected an expression such as expr(published == true), got: #{inspect(expression)}

    Conditions are written with Backpex.Expr.expr/1, see the guide on upgrading to v0.24.
    """
  end
end
