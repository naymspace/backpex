defmodule DocTest do
  use ExUnit.Case, async: true

  alias Backpex.HTML
  alias Backpex.HTML.Layout
  alias Backpex.HTML.Resource
  alias Backpex.LiveResource
  alias Backpex.ResourceAction
  alias Backpex.Router

  doctest LiveResource
  doctest ResourceAction
  doctest Backpex.Resource
  doctest Router
  doctest Backpex.Fields.Upload
  doctest HTML
  doctest Layout
  doctest Resource
end
