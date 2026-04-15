defmodule DocTest do
  use ExUnit.Case, async: true

  alias Backpex.Fields.Upload
  alias Backpex.HTML.Layout
  alias Backpex.HTML.Resource

  doctest Backpex.LiveResource
  doctest Backpex.ResourceAction
  doctest Backpex.Resource
  doctest Backpex.Router
  doctest Upload
  doctest Backpex.HTML
  doctest Layout
  doctest Resource
end
