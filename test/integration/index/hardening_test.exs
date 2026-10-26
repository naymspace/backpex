defmodule Backpex.Integration.Index.HardeningTest do
  use Backpex.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "ignores a search param that is not a string", %{conn: conn} do
    insert(:post, title: "Alpha Post")
    insert(:post, title: "Beta Post")

    # `search[a]=b` decodes to a map, which used to raise in the dead render (HTTP 500).
    path = ~p"/admin/posts?#{%{"search" => %{"a" => "b"}, "filters" => %{"published" => ["published"]}}}"

    assert conn |> get(path) |> html_response(200)

    conn
    |> visit(path)
    |> assert_has("table tbody tr", count: 2)
    |> assert_has("#index-search-form input[value='']")
  end

  test "falls back to the defaults for a tampered page size or search event", %{conn: conn} do
    insert_list(20, :post)

    {:ok, view, _html} = live(conn, ~p"/admin/posts?#{%{"filters" => %{"published" => ["published"]}}}")
    default_rows = view |> render() |> rows()
    assert default_rows in 1..19

    for value <- ["abc", "15abc", %{"a" => "b"}] do
      render_hook(view, "select-page-size", %{"select_per_page" => %{"value" => value}})
      assert_patch(view)
      assert view |> render() |> rows() == default_rows
    end

    render_hook(view, "index-search", %{"index_search" => %{"value" => %{"a" => "b"}}})
    assert_patch(view)
    assert view |> render() |> rows() == default_rows
    assert has_element?(view, "#index-search-form input[value='']")
  end

  test "ignores filter values of the wrong shape in the URL", %{conn: conn} do
    insert(:post, title: "Published Post", published: true)
    insert(:post, title: "Draft Post", published: false)

    for query <- [
          "filters[published]=published&filters[likes]=abc",
          "filters[likes][start][a]=b&filters[inserted_at][end][a]=b"
        ] do
      {:ok, _view, html} = live(conn, "/admin/posts?" <> query)

      assert html =~ "Published Post"
      assert html =~ "Draft Post"
    end
  end

  test "drops persisted filter values of the wrong shape on the next filter change", %{conn: conn} do
    insert(:post, title: "Published Post", published: true)
    insert(:post, title: "Draft Post", published: false)

    session = %{
      "backpex_preferences" => %{
        "resource" => %{
          "Backpex.Test.PostLive" => %{
            "filters" => %{"published" => "published", "likes" => %{"start" => %{"a" => "b"}, "end" => ""}}
          }
        }
      }
    }

    conn = Plug.Test.init_test_session(conn, session)

    changes = [
      fn view -> view |> form("#filter-form", filters: %{published: ["published"]}) |> render_change() end,
      fn view -> render_click(view, "clear-filter", %{"field" => "category_id"}) end,
      fn view -> render_click(view, "filter-preset-selected", %{"field" => "likes", "preset-index" => "0"}) end
    ]

    for change <- changes do
      {:ok, view, html} = live(conn, ~p"/admin/posts")

      assert html =~ "Published Post"
      assert html =~ "Draft Post"

      change.(view)

      path = view |> assert_patch() |> URI.decode()
      refute path =~ "filters[published]=published"
      refute path =~ "[a]=b"
    end
  end

  defp rows(html), do: html |> LazyHTML.from_document() |> LazyHTML.query("table tbody tr") |> Enum.count()
end
