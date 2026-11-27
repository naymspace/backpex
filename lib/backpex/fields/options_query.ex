defmodule Backpex.Fields.OptionsQuery do
  @moduledoc false
  # What the relation fields share to load their options and to check submitted values against their `options_query`.

  import Ecto.Query

  alias Phoenix.HTML.Form

  @default_query_limit 10

  @doc """
  Whether the field searches its options on the server, i.e. its `searchable_options` is `:server`.
  """
  def server_search?(field_options), do: Map.get(field_options, :searchable_options) == :server

  @doc """
  The number of options a page holds with server search: the `query_limit` of the field, `#{@default_query_limit}` if
  it has none. An explicit `nil` loads every option.
  """
  def query_limit(field_options), do: Map.get(field_options, :query_limit, @default_query_limit)

  @doc """
  Refuses a `query_limit` without server search, as only server search loads the options page by page.
  """
  def validate_search!(validated_options, {name, _options} = _field, live_resource) do
    if Keyword.has_key?(validated_options, :query_limit) and validated_options[:searchable_options] != :server do
      raise """
      Configuration error for field "#{name}" in "#{live_resource}".

      `query_limit` only applies with `searchable_options: :server`, which loads the options page by page.
      """
    end

    validated_options
  end

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
    query
    |> all(criteria, opts)
    |> Enum.map(&to_option(&1, opts))
  end

  @doc """
  Loads the records of the options that `list/3` returns.
  """
  def all(query, criteria, opts) do
    {offset, limit} = {criteria[:offset], criteria[:limit]}

    query
    |> filter(criteria, opts)
    |> maybe_order_page(opts[:value], offset || limit)
    |> maybe_offset(offset)
    |> maybe_limit(limit)
    |> opts[:repo].all()
  end

  @doc """
  Returns the record as a `{label, value}` option.
  """
  def to_option(record, opts), do: {Map.get(record, opts[:label]), Map.fetch!(record, opts[:value])}

  @doc """
  Loads a page of `:limit` options with `list/3` and tells whether more options follow.

  It loads one option more than the page holds instead of counting the options.
  """
  def page(query, criteria, opts) do
    {records, more} = page_records(query, criteria, opts)

    {Enum.map(records, &to_option(&1, opts)), more}
  end

  @doc """
  Loads the records of the options that `page/3` returns and tells whether more options follow.
  """
  def page_records(query, criteria, opts) do
    case criteria[:limit] do
      nil ->
        {all(query, criteria, opts), false}

      limit ->
        records = all(query, Keyword.put(criteria, :limit, limit + 1), opts)

        {Enum.take(records, limit), length(records) > limit}
    end
  end

  @doc """
  Assigns a page of options with `page_records/3`: the records as `:option_records`, them as options as `:options` and
  whether more follow as `:show_more`. `opts_fun` returns the `opts` of `list/3` for the assigns.

  The page holds the options of the assigns' `:options_base_query` that match their `:search_input`, from their
  `:offset` on, and follows `previous_records`, e.g. the records of the pages before with "Show more". Without server
  search it holds every option.
  """
  def assign_page(socket, opts_fun, previous_records \\ []) do
    %{assigns: %{field_options: field_options, search_input: search_input, offset: offset} = assigns} = socket
    opts = opts_fun.(assigns)
    criteria = [search: search_input, offset: offset, limit: page_limit(field_options)]

    {records, show_more} = page_records(assigns.options_base_query, criteria, opts)
    records = previous_records ++ records

    Phoenix.Component.assign(socket,
      option_records: records,
      options: Enum.map(records, &to_option(&1, opts)),
      show_more: show_more
    )
  end

  @doc """
  Handles the `search` event of the combobox, which it pushes with the text of its search input, and with an empty
  text when its popup closes. Loads the first page of the matching options.

  A field without server search or without loaded options ignores it, as a crafted client can send it anyway.
  """
  def handle_search(socket, %{"query" => query}, opts_fun) when is_binary(query) do
    if searching?(socket) do
      socket
      |> Phoenix.Component.assign(search_input: query, offset: 0)
      |> assign_page(opts_fun)
    else
      socket
    end
  end

  def handle_search(socket, _params, _opts_fun), do: socket

  @doc """
  Handles the `show-more` event of the "Show more" button: loads the next page and appends it to the options.
  """
  def handle_show_more(socket, opts_fun) do
    %{assigns: %{field_options: field_options} = assigns} = socket

    case query_limit(field_options) do
      limit when is_integer(limit) ->
        if searching?(socket) do
          socket
          |> Phoenix.Component.assign(:offset, assigns.offset + limit)
          |> assign_page(opts_fun, assigns.option_records)
        else
          socket
        end

      nil ->
        socket
    end
  end

  defp searching?(%{assigns: assigns}) do
    server_search?(assigns.field_options) and Map.has_key?(assigns, :options_base_query) and
      Map.has_key?(assigns, :option_records)
  end

  @doc """
  The limit of a page: the `query_limit` with server search, else none.
  """
  def page_limit(field_options) do
    if server_search?(field_options), do: query_limit(field_options)
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
