defmodule Backpex.Fields.OptionsQuery do
  @moduledoc false
  # What the relation fields share to load their options and to check submitted values against their `options_query`.

  import Ecto.Query

  alias Phoenix.HTML.Form

  @doc """
  Loads the options of the options query as `{label, value}` tuples.

  These criteria limit the options:

    * `:search` - only the options whose `:search_by` contains this string, ignoring case. Ignored if it is `nil` or
      blank.
    * `:ids` - only the options whose `:value` is one of these values.
    * `:offset` and `:limit` - skip and limit the options. Ignored if they are `nil`. With either of them, the options
      are also ordered by their `:value`, so that pages neither overlap nor skip options when the options query has no
      order or orders by a column with equal values.

  The `opts` tell how the field reads its options:

    * `:repo` - the repo that loads them.
    * `:queryable` - the schema of the options.
    * `:label` and `:value` - the fields of an option that are its label and value.
    * `:search_by` - a field of the first binding or a `dynamic` expression that `:search` is matched against.
  """
  def list(query, criteria, opts) do
    {offset, limit} = {criteria[:offset], criteria[:limit]}

    query
    |> filter(criteria, opts)
    |> maybe_order_page(opts[:value], offset || limit)
    |> maybe_offset(offset)
    |> maybe_limit(limit)
    |> opts[:repo].all()
    |> Enum.map(&{Map.get(&1, opts[:label]), Map.fetch!(&1, opts[:value])})
  end

  @doc """
  Loads a page of `:limit` options with `list/3` and tells whether more options follow.

  It loads one option more than the page holds instead of counting the options.
  """
  def page(query, criteria, opts) do
    case criteria[:limit] do
      nil ->
        {list(query, criteria, opts), false}

      limit ->
        options = list(query, Keyword.put(criteria, :limit, limit + 1), opts)

        {Enum.take(options, limit), length(options) > limit}
    end
  end

  @doc """
  Assigns a page of options with `page/3` and whether more follow, as `:options` and `:show_more`.

  The page starts at the `:offset` of the assigns and matches their `:search_input`, and the options of the assigns'
  `:options_base_query`. The page follows `other_options`, e.g. the options of the pages before with "Show more".
  """
  def assign_page(socket, opts, other_options \\ []) do
    %{assigns: %{field_options: field_options, search_input: search_input, offset: offset} = assigns} = socket
    criteria = [search: search_input, offset: offset, limit: field_options[:query_limit]]

    {options, show_more} = page(assigns.options_base_query, criteria, opts)

    Phoenix.Component.assign(socket, options: other_options ++ options, show_more: show_more)
  end

  @doc """
  Counts the options `list/3` returns for the criteria, ignoring `:offset` and `:limit`.
  """
  def count(query, criteria, opts) do
    query
    |> filter(criteria, opts)
    |> subquery()
    |> opts[:repo].aggregate(:count)
  end

  defp filter(query, criteria, opts) do
    query
    |> maybe_with_ids(criteria[:ids], opts)
    |> maybe_search(criteria[:search], opts[:search_by])
  end

  defp maybe_with_ids(query, nil, _opts), do: query
  defp maybe_with_ids(query, ids, opts), do: with_ids(query, opts[:queryable], opts[:value], ids)

  defp maybe_search(query, nil, _search_by), do: query

  defp maybe_search(query, search, search_by) do
    if String.trim(search) == "" do
      query
    else
      search = "%#{search}%"

      case search_by do
        %Ecto.Query.DynamicExpr{} = expression -> where(query, ^dynamic(ilike(^expression, ^search)))
        field -> where(query, [option], ilike(field(option, ^field), ^search))
      end
    end
  end

  # Appended to the order of the options query, so it only orders options that are equal by that order.
  defp maybe_order_page(query, _key, nil), do: query
  defp maybe_order_page(query, key, _page), do: order_by(query, [option], field(option, ^key))

  defp maybe_offset(query, nil), do: query
  defp maybe_offset(query, offset), do: offset(query, ^offset)

  defp maybe_limit(query, nil), do: query
  defp maybe_limit(query, limit), do: limit(query, ^limit)

  @doc """
  Puts a form of the submitted attrs into the assigns the options query receives.

  The assigns of the form hold the form of the previous event, so an options query that reads another value of the form
  would be checked against the value before this event.
  """
  def put_submitted_form(%{form: %Form{name: name}} = assigns, %Ecto.Changeset{} = changeset, attrs)
      when is_map(attrs) do
    Map.put(assigns, :form, Phoenix.Component.to_form(%{changeset | params: attrs}, as: name))
  end

  def put_submitted_form(assigns, _changeset, _attrs), do: assigns

  @doc """
  Limits the options query to the options whose `key` is one of the given ids.

  The database applies a `where` before `limit` and `offset`, so a query with one of them keeps them in a subquery.
  Otherwise a record the select doesn't offer would count as an option.
  """
  def with_ids(%Ecto.Query{limit: nil, offset: nil} = query, _queryable, key, ids) do
    where(query, [option], field(option, ^key) in ^ids)
  end

  def with_ids(query, queryable, key, ids) do
    option_ids =
      query
      |> exclude(:select)
      |> exclude(:preload)
      |> select([option], field(option, ^key))

    where(queryable, [option], field(option, ^key) in ^ids and field(option, ^key) in subquery(option_ids))
  end
end
