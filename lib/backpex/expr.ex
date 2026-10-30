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

  ## Values

  Expressions are values, too, e.g. the computed values of a LiveResource (see `c:Backpex.LiveResource.computed/1`): a
  field such as `author.name`, a condition such as `likes > 0`, or a string of fields:

    * `concat(parts, separator)` - joins the strings of the fields and strings in `parts` with the optional
      `separator`, e.g. `expr(concat([first_name, last_name], " "))`. Like `concat_ws` in SQL, it leaves out `nil`.
    * `+`, `-`, `*` and `/` - compute with numbers, e.g. `expr(likes - dislikes)`. As in SQL, the division of two
      integers is an integer, rounded towards zero, and a value with `nil` is `nil`.
    * `datetime_diff(left, right, unit)` - the time from the datetime `right` to the datetime `left` as an integer of
      whole `:second`, `:minute`, `:hour` or `:day` units, rounded towards zero, e.g.
      `expr(datetime_diff(ends_at, starts_at, :minute))`.
    * `to_string(value)` - the value as a string, e.g. `expr(to_string(likes))`.

  Comparisons take values on both sides, e.g. `expr(likes - dislikes > 10)` or `expr(concat([street, city]) != "")`.

  `aggregate/3` computes a value of related items, e.g. the number of the posts of a user or the name of the author of
  the newest comment.

  ## Keyword lists

  Wherever Backpex takes an expression, a keyword list stands for fields that equal values, e.g. `[published: true]` is
  `expr(published == true)`. Use it for simple conditions such as the `:where` of a metric.

  ## Expressions of the adapter

  An expression that only the adapter can express, e.g. a fragment of SQL, is wrapped with `native/3`. The adapter
  takes it as it is, and other adapters refuse it:

      Backpex.Expr.native(Backpex.Adapters.Ecto, dynamic([post], fragment("lower(?)", post.title) == ^title))

  With `uses: [:author]`, a native expression reads the fields of related items. The adapter joins the relationships
  first, see the adapter for how the expression refers to them.

  ## Checking and casting

  `cast/2` checks the fields of an expression against the description of the resource (see
  `c:Backpex.Adapter.describe/2`) and casts the values to the types of the fields, so an adapter gets e.g. `10` for
  `expr(likes >= "10")`. Adapters call it through `Backpex.Resource.cast_expr/2` before they turn an expression into a
  query. It raises for unknown fields and relationships, so a typo in a filter fails with a clear message.

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
    `:ends_with`, `:and`, `:or`, `:not`, `:concat`, `:+`, `:-`, `:*`, `:/`, `:datetime_diff` and `:to_string`. `opts`
    holds the options of a function, e.g. `ignore_case: true`, the `:separator` of `concat` or the `:unit` of
    `datetime_diff`.
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

  defmodule Aggregate do
    @moduledoc """
    A value of the related items at the end of `path`, e.g. their number, see `Backpex.Expr.aggregate/3`.
    """

    @enforce_keys [:kind, :path]
    defstruct kind: nil, path: [], value: nil, where: nil, sort: []

    @type t :: %__MODULE__{
            kind: :first | :count | :sum | :avg | :min | :max,
            path: [atom(), ...],
            value: Backpex.Expr.t() | nil,
            where: Backpex.Expr.t() | nil,
            sort: [{Backpex.Expr.Ref.t(), atom()}]
          }
  end

  defmodule Native do
    @moduledoc """
    An expression that only `adapter` understands, see `Backpex.Expr.native/3`. `uses` lists the paths of relationships
    whose fields it reads.
    """

    @enforce_keys [:adapter, :expr]
    defstruct adapter: nil, expr: nil, uses: []

    @type t :: %__MODULE__{adapter: module(), expr: term(), uses: [[atom()]]}
  end

  @typedoc """
  An expression, see the module documentation.
  """
  @type t :: Ref.t() | Call.t() | Exists.t() | Aggregate.t() | Native.t()

  @comparisons [:==, :!=, :<, :<=, :>, :>=]
  @string_functions [:contains, :starts_with, :ends_with]
  @arithmetic [:+, :-, :*, :/]
  @datetime_units [:second, :minute, :hour, :day]

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
      iex> expr(likes - dislikes > 10)
      %Backpex.Expr.Call{
        name: :>,
        args: [
          %Backpex.Expr.Call{
            name: :-,
            args: [%Backpex.Expr.Ref{path: [], name: :likes}, %Backpex.Expr.Ref{path: [], name: :dislikes}]
          },
          10
        ]
      }

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

  defp build({operator, _meta, [left, right]}, caller) when operator in @arithmetic do
    call(operator, [build(left, caller), build(right, caller)])
  end

  defp build({:-, _meta, [number]}, _caller) when is_number(number), do: -number

  defp build({:datetime_diff, meta, [left, right, unit]}, caller) do
    if unit not in @datetime_units do
      compile_error!(caller, meta, "expected the unit of datetime_diff/3 to be one of #{inspect(@datetime_units)}")
    end

    quote do
      %Call{
        name: :datetime_diff,
        args: [unquote(build(left, caller)), unquote(build(right, caller))],
        opts: [unit: unquote(unit)]
      }
    end
  end

  defp build({:to_string, _meta, [value]}, caller), do: call(:to_string, [build(value, caller)])

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

  defp build({:concat, meta, [parts]}, caller), do: build_concat(parts, "", meta, caller)
  defp build({:concat, meta, [parts, separator]}, caller), do: build_concat(parts, separator, meta, caller)

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

  defp build_concat(parts, separator, _meta, caller) when is_list(parts) do
    quote do
      %Call{
        name: :concat,
        args: unquote(build(parts, caller)),
        opts: [separator: unquote(build(separator, caller))]
      }
    end
  end

  defp build_concat(parts, _separator, meta, caller) do
    compile_error!(caller, meta, "expected a list of fields and strings in concat, got: #{show(parts)}")
  end

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
    "Expressions support ==, !=, <, <=, >, >=, in, and, or, not, +, -, *, /, is_nil/1, contains/2, starts_with/2, " <>
      "ends_with/2, exists/2, concat/1, concat/2, datetime_diff/3, to_string/1, ref/1 and ref/2, see Backpex.Expr"
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
  @spec native(module(), term(), keyword()) :: Native.t()
  def native(adapter, expression, opts \\ []) when is_atom(adapter) do
    %Native{adapter: adapter, expr: expression, uses: opts |> Keyword.get(:uses, []) |> Enum.map(&List.wrap/1)}
  end

  @doc """
  Returns a value of the related items at the end of `path`, a relationship or a list of relationships, e.g. as a
  computed value (see `c:Backpex.LiveResource.computed/1`). `kind` is one of:

    * `:count` - the number of related items.
    * `:sum`, `:avg`, `:min` and `:max` - the sum, average, minimum or maximum of the `:value`, `nil` for no items.
    * `:first` - the `:value` of the first related item after the `:sort`, `nil` for no items.

  ## Options

    * `:value` - an expression of the related items, e.g. `expr(amount)` or `expr(author.name)`. Required for every kind
      except `:count`.
    * `:where` - an expression that limits the related items.
    * `:sort` - the order of the related items for `:first`, like `Backpex.Query.sort/2`.

  ## Examples

      Backpex.Expr.aggregate(:count, :posts, where: expr(published == true))

      Backpex.Expr.aggregate(:first, :comments, value: expr(author.name), sort: [inserted_at: :desc])
  """
  @spec aggregate(Aggregate.t() | atom(), atom() | [atom()], keyword()) :: Aggregate.t()
  def aggregate(kind, path, opts \\ []) when kind in [:first, :count, :sum, :avg, :min, :max] do
    value = opts[:value] && normalize(opts[:value])

    if kind != :count and is_nil(value) do
      raise ArgumentError, "expected a :value for the aggregate #{inspect(kind)} of #{inspect(path)}"
    end

    sort =
      opts
      |> Keyword.get(:sort, [])
      |> Enum.map(fn
        {%Ref{} = ref, direction} -> {ref, direction}
        {name, direction} when is_atom(name) -> {ref(name), direction}
      end)

    %Aggregate{kind: kind, path: List.wrap(path), value: value, where: normalize(opts[:where]), sort: sort}
  end

  @doc """
  Returns the expression for the items at the end of `path`, e.g. a value of the related items of `[:author]` as a
  value of the items: the paths of its refs start with `path`.

      iex> import Backpex.Expr
      iex> expr(concat([first_name, last_name], " ")) |> Backpex.Expr.prefix([:author])
      %Backpex.Expr.Call{
        name: :concat,
        args: [%Backpex.Expr.Ref{path: [:author], name: :first_name}, %Backpex.Expr.Ref{path: [:author], name: :last_name}],
        opts: [separator: " "]
      }
  """
  @spec prefix(t(), [atom()]) :: t()
  def prefix(expression, []), do: expression
  def prefix(%Ref{path: own_path} = ref, path), do: %{ref | path: path ++ own_path}
  def prefix(%Call{args: args} = call, path), do: %{call | args: Enum.map(args, &prefix_arg(&1, path))}
  def prefix(%Exists{path: own_path} = exists, path), do: %{exists | path: path ++ own_path}
  def prefix(%Aggregate{path: own_path} = aggregate, path), do: %{aggregate | path: path ++ own_path}

  def prefix(%Native{} = expression, path) do
    raise ArgumentError, "can't use the native expression #{inspect(expression)} for the items of #{inspect(path)}"
  end

  defp prefix_arg(%struct{} = expression, path) when struct in [Ref, Call, Exists, Aggregate, Native],
    do: prefix(expression, path)

  defp prefix_arg(value, _path), do: value

  @doc """
  Checks the fields of the expression and casts the values compared to a field to the type of the field.

  `describe` returns the `Backpex.Adapter.Description` of the items at the end of a path of relationships, or `nil` if
  there is no such path, e.g. `&Backpex.Resource.describe(&1, live_resource)`. The values of comparisons and of `in`
  are cast to the `:type` of their field. A value that can't be cast is kept as it is, so the adapter decides about it.
  The values of `contains/2`, `starts_with/2` and `ends_with/2` are kept, as they are parts of strings.

  Raises an `ArgumentError` for an unknown field or relationship and for a path through a relationship to many items.
  Native expressions are kept as they are.
  """
  @spec cast(t() | keyword() | nil, ([atom()] -> Backpex.Adapter.Description.t() | nil)) :: t() | nil
  def cast(expression, describe) when is_function(describe, 1) do
    expression |> normalize() |> cast_in([], describe)
  end

  defp cast_in(nil, _base, _describe), do: nil
  defp cast_in(%Native{} = expression, _base, _describe), do: expression
  defp cast_in(%Ref{} = ref, base, describe), do: cast_arg(ref, base, describe)

  defp cast_in(%Aggregate{path: path, value: value, where: where} = aggregate, base, describe) do
    path = base ++ path
    description!(path, describe)

    %{
      aggregate
      | value: value |> normalize() |> cast_in(path, describe),
        where: where |> normalize() |> cast_in(path, describe)
    }
  end

  defp cast_in(%Exists{path: path, where: where} = expression, base, describe) do
    path = base ++ path
    description!(path, describe)

    %{expression | where: where |> normalize() |> cast_in(path, describe)}
  end

  defp cast_in(%Call{name: name, args: [%Ref{} = ref, value]} = call, base, describe) when name in @comparisons do
    %{call | args: [ref, cast_field_value(field!(ref, base, describe), value)]}
  end

  defp cast_in(%Call{name: name, args: [value, %Ref{} = ref]} = call, base, describe) when name in @comparisons do
    %{call | args: [cast_field_value(field!(ref, base, describe), value), ref]}
  end

  defp cast_in(%Call{name: :in, args: [%Ref{} = ref, values]} = call, base, describe) when is_list(values) do
    field = field!(ref, base, describe)

    %{call | args: [ref, Enum.map(values, &cast_field_value(field, &1))]}
  end

  defp cast_in(%Call{args: args} = call, base, describe) do
    %{call | args: Enum.map(args, &cast_arg(&1, base, describe))}
  end

  defp cast_arg(%Ref{} = ref, base, describe) do
    field!(ref, base, describe)
    ref
  end

  defp cast_arg(%struct{} = expression, base, describe) when struct in [Call, Exists, Aggregate, Native],
    do: cast_in(expression, base, describe)

  defp cast_arg(value, _base, _describe), do: value

  # The field of the ref, after checking that its path goes through relationships to one item.
  defp field!(%Ref{path: path, name: name}, base, describe) do
    path
    |> Enum.with_index()
    |> Enum.each(fn {relationship, index} ->
      case description!(base ++ Enum.take(path, index), describe).relationships do
        %{^relationship => %{cardinality: :one}} ->
          :ok

        %{^relationship => _many} ->
          raise ArgumentError,
                "expected #{inspect(relationship)} to be a relationship to one item in the path of " <>
                  "#{inspect(name)}, use exists(#{relationship}, ...) for a relationship to many items"

        _relationships ->
          raise ArgumentError, "unknown relationship #{inspect(relationship)} in the path of #{inspect(name)}"
      end
    end)

    %{fields: fields} = description!(base ++ path, describe)

    Map.get(fields, name) || raise ArgumentError, "unknown field #{inspect(name)} in #{inspect(base ++ path)}"
  end

  defp description!(path, describe) do
    describe.(path) || raise ArgumentError, "unknown relationship path #{inspect(path)}"
  end

  defp cast_field_value(_field, nil), do: nil

  defp cast_field_value(%{type: type}, value) do
    case cast_value(type, value) do
      {:ok, value} -> value
      :error -> value
    end
  end

  @doc """
  Casts a value to a type of the description of a resource, see `Backpex.Adapter.Description`.

      iex> Backpex.Expr.cast_value(:integer, "10")
      {:ok, 10}

      iex> Backpex.Expr.cast_value(:integer, "ten")
      :error
  """
  @spec cast_value(term(), term()) :: {:ok, term()} | :error
  def cast_value(type, value) do
    case Ecto.Changeset.cast({%{}, %{value: type}}, %{value: value}, [:value], empty_values: []) do
      %{valid?: true} = changeset -> {:ok, Ecto.Changeset.get_field(changeset, :value)}
      _changeset -> :error
    end
  end

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
  def normalize(%struct{} = expression) when struct in [Ref, Call, Exists, Aggregate, Native], do: expression

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

    Conditions are written with Backpex.Expr.expr/1, see the guide on upgrading to v0.24. Wrap an expression of the
    adapter, e.g. an Ecto dynamic expression, with Backpex.Expr.native(Backpex.Adapters.Ecto, dynamic(...)).
    """
  end
end
