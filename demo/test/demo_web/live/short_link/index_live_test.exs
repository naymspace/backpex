defmodule DemoWeb.Live.ShortLink.IndexLiveTest do
  use DemoWeb.ConnCase, async: false

  import Demo.EctoFactory

  alias Demo.Repo
  alias Demo.ShortLink

  describe "short-links live resource index" do
    test "is rendered", %{conn: conn} do
      insert_list(3, :short_link)

      conn
      |> visit(~p"/admin/short-links")
      |> assert_has("h1", text: "Short Links", exact: true)
      |> assert_has("button", text: "New Short Link", exact: true)
      |> assert_has("table tbody tr", count: 3)
    end
  end

  describe "short-link authorization (no delete)" do
    setup do
      product = insert(:product)

      {:ok, short_link} =
        Repo.insert(%ShortLink{short_key: "test123", url: "https://example.com", product_id: product.id})

      %{short_link: short_link}
    end

    test "delete button not rendered", %{conn: conn, short_link: short_link} do
      # ShortLink uses short_key as primary key, not id
      conn
      |> visit(~p"/admin/short-links")
      |> refute_has("button[aria-label='Delete'][phx-value-item-id='#{short_link.short_key}']")
    end
  end
end
