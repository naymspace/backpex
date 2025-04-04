defmodule DocTest do
  use ExUnit.Case, async: true

  doctest Backpex.LiveResource
  doctest Backpex.ResourceAction
  doctest Backpex.Resource
  doctest Backpex.Router
  doctest Backpex.Fields.Upload
  doctest Backpex.HTML
  doctest Backpex.HTML.Layout
  doctest Backpex.HTML.Resource
end
