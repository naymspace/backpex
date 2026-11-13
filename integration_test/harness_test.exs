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
      item = live_resource.adapter_config(:schema) |> build_with_factory()

      case live_resource.config(:adapter) do
        Memory -> live_resource.adapter_config(:store) |> Memory.put_items([item])
        _adapter -> insert(item)
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
