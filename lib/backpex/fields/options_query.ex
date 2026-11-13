defmodule Backpex.Fields.OptionsQuery do
  @moduledoc false
  # What the relation fields share to check submitted values against their `options_query`. The adapter limits the
  # options to the submitted ids, see the `:ids` criterion of `c:Backpex.Adapter.list_options/4`.

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
  Tells whether a submitted value is the stored value `stored`.

  The form renders a stored value as a string, so the client submits it the same way. A value in any other spelling,
  e.g. with a leading zero, counts as another value and has to be an option.
  """
  def same_value?(nil = _stored, _value), do: false

  def same_value?(stored, value) when is_binary(value) or is_integer(value) do
    to_string(stored) == to_string(value)
  end

  def same_value?(_stored, _value), do: false
end
