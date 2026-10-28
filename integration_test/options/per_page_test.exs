defmodule Backpex.Integration.Options.PerPageTest do
  @moduledoc """
  Checks the `per_page_default` and `per_page_options` options. `Backpex.Test.PagedNoteLive` sets
  `per_page_options: [3, 6, 12]` and `per_page_default: 6`; the defaults (`[15, 50, 100]` and `15`) are checked in
  `Backpex.Integration.Index.PaginationTest`.
  """
  use Backpex.ConnCase, async: true

  setup do
    insert_list(8, :note)
    :ok
  end

  test "shows per_page_default items per page", %{conn: conn} do
    conn
    |> visit(~p"/admin/paged-notes")
    |> assert_has("table tbody tr", count: 6)
    |> assert_has("div", text: "Items 1 to 6 (8 total)", exact: true)
  end

  test "offers the per_page_options in the page size select with per_page_default selected", %{conn: conn} do
    conn
    |> visit(~p"/admin/paged-notes")
    |> assert_has("#select-per-page-form option", count: 3)
    |> assert_has("#select-per-page-form option[value='3']", text: "3")
    |> assert_has("#select-per-page-form option[value='6'][selected]", text: "6")
    |> assert_has("#select-per-page-form option[value='12']", text: "12")
  end

  test "selecting a page size of the per_page_options changes the page size", %{conn: conn} do
    conn
    |> visit(~p"/admin/paged-notes")
    |> select("Items per page", option: "3")
    |> assert_has("table tbody tr", count: 3)
    |> assert_has("div", text: "Items 1 to 3 (8 total)", exact: true)
    |> assert_has("#select-per-page-form option[value='3'][selected]")
  end

  for {per_page, rows} <- [{"3", 3}, {"12", 8}] do
    test "uses the per_page param #{per_page} of the per_page_options", %{conn: conn} do
      conn
      |> visit(~p"/admin/paged-notes?#{%{"per_page" => unquote(per_page)}}")
      |> assert_has("table tbody tr", count: unquote(rows))
    end
  end

  # 15 is one of the default `per_page_options`, but not of the configured ones.
  for per_page <- ["15", "invalid"] do
    test "falls back to per_page_default for the per_page param #{inspect(per_page)}", %{conn: conn} do
      conn
      |> visit(~p"/admin/paged-notes?#{%{"per_page" => unquote(per_page)}}")
      |> assert_has("table tbody tr", count: 6)
      |> assert_has("div", text: "Items 1 to 6 (8 total)", exact: true)
    end
  end
end
