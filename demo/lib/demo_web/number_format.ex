defmodule DemoWeb.NumberFormat do
  @moduledoc """
  Number formatting helpers for the demo LiveResources.
  """

  @doc """
  Formats a number as an integer string using `.` as thousands delimiter.

  ## Examples

      iex> DemoWeb.NumberFormat.to_delimited(1_234_567)
      "1.234.567"

      iex> DemoWeb.NumberFormat.to_delimited(-1_234)
      "-1.234"

      iex> DemoWeb.NumberFormat.to_delimited(nil)
      nil
  """
  def to_delimited(nil), do: nil

  def to_delimited(value) do
    value
    |> to_integer()
    |> Integer.to_string()
    |> delimit()
  end

  defp to_integer(value) when is_integer(value), do: value
  defp to_integer(value) when is_float(value), do: round(value)
  defp to_integer(%Decimal{} = value), do: value |> Decimal.round(0) |> Decimal.to_integer()

  defp delimit("-" <> digits), do: "-" <> delimit(digits)

  defp delimit(digits) do
    digits
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.map_join(".", &Enum.join/1)
    |> String.reverse()
  end
end
