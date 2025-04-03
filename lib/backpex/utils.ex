defmodule Backpex.Utils do
  @moduledoc false

  @doc """
  Returns the "parent" module name.

  ### Example

    iex> Elixir.DemoWeb.FilmReviewLive.Index
    Elixir.DemoWeb.FilmReviewLive
  """
  def parent_module(module) do
    module
    |> Module.split()
    |> Enum.reverse()
    |> tl()
    |> Kernel.++(["Elixir"])
    |> Enum.reverse()
    |> Enum.join(".")
    |> String.to_existing_atom()
  end
end
