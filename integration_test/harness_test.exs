defmodule Backpex.Integration.HarnessTest do
  use Backpex.ConnCase, async: true

  alias Backpex.Adapters.Memory
  alias Backpex.Test.EctoFactory

  test "renders the index view of every routed LiveResource", %{conn: conn} do
    live_routes =
      for %{path: path, metadata: %{phoenix_live_view: {view, action, _opts, _extra}}} <-
            Phoenix.Router.routes(Backpex.Test.Router) do
        {path, view |> Module.split() |> Enum.drop(-1) |> Module.safe_concat(), action}
      end

    index_routes = for {path, live_resource, :index} <- live_routes, do: {path, live_resource}

    # Every routed LiveResource has an index route, so none is skipped below.
    assert index_routes != []

    assert index_routes |> Enum.map(&elem(&1, 1)) |> Enum.sort() ==
             live_routes |> Enum.map(&elem(&1, 1)) |> Enum.uniq() |> Enum.sort()

    for {_path, live_resource} <- index_routes do
      schema = live_resource.adapter_config(:schema)
      item = build_with_factory(schema)

      # Items of an embedded schema are kept in the store of `Backpex.Adapters.Memory`, not in the database.
      if schema.__schema__(:source) do
        insert(item)
      else
        store = live_resource.adapter_config(:store)
        Memory.put_items(store, [item | Memory.items(store)])
      end
    end

    for {path, live_resource} <- index_routes do
      conn
      |> visit(path)
      |> assert_has("h1", text: live_resource.plural_name(), exact: true)
      |> assert_has("table tbody tr")
    end
  end

  # The factory of a schema is named after it, e.g. `film_review_factory/0` for `Backpex.Test.FilmReview`.
  defp build_with_factory(schema) do
    name = (schema |> Module.split() |> List.last() |> Macro.underscore()) <> "_factory"
    factories = EctoFactory.__info__(:functions)
    {factory, 0} = Enum.find(factories, fn {function, arity} -> arity == 0 and Atom.to_string(function) == name end)

    apply(EctoFactory, factory, [])
  end
end
