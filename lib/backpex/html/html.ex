defmodule Backpex.HTML do
  @moduledoc """
  Contains common HTML functions.
  """

  @doc """
  Prettifies any input and show a placeholder in case the value is `nil`.

  ## Examples

      iex> Backpex.HTML.pretty_value(nil)
      "—"

      iex> Backpex.HTML.pretty_value("")
      "—"

      iex> Backpex.HTML.pretty_value(1_000_000)
      1000000

      iex> Backpex.HTML.pretty_value(1.11)
      1.11

      iex> Backpex.HTML.pretty_value("Hello, universe")
      "Hello, universe"
  """
  def pretty_value(input) when is_nil(input) or input == "", do: "—"
  def pretty_value(input), do: input
end
