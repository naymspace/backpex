defmodule Backpex.ReadonlyField do
  @moduledoc ~S"""
  Behaviour to implement if fields should be able to render a readonly version.
  """

  @doc """
  Used to render the readonly version of the field.
  """
  @callback render_form_readonly(assigns :: map()) :: %Phoenix.LiveView.Rendered{}

  @doc """
  Determine if the field should be rendered as readonly version.
  """
  def is_readonly?(%{readonly: readonly}, _assigns) when is_boolean(readonly) do
    readonly
  end

  def is_readonly?(%{readonly: readonly}, assigns) when is_function(readonly) do
    readonly.(assigns)
  end

  def is_readonly?(_field, _assigns) do
    false
  end
end
