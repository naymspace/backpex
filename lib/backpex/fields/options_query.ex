defmodule Backpex.Fields.OptionsQuery do
  @moduledoc false
  # What the relation fields share to check submitted values against their `options_query`.

  import Ecto.Query

  alias Phoenix.HTML.Form

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
