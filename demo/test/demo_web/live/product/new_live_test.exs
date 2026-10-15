defmodule DemoWeb.Live.Product.NewLiveTest do
  use DemoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Demo.Product
  alias Demo.Repo

  describe "products live resource new" do
    test "is rendered", %{conn: conn} do
      conn
      |> visit(~p"/admin/products/new")
      |> assert_has("h1", text: "New Product", exact: true)
      |> assert_has("button", text: "Cancel", exact: true)
      |> assert_has("button", text: "Save", exact: true)
    end
  end

  # The browser doesn't submit a form while a file input has refused files, but a save event can still reach the server.
  describe "saving while an upload has refused files" do
    test "refuses a file that's too large next to a valid one", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/products/new")

      upload_images(view, [image("small.jpg", 100), image("big.jpg", 600_000)])

      view
      |> submit_form()
      |> assert_save_refused(view)
    end

    test "refuses too many files", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/products/new")

      upload_images(view, [image("one.jpg", 100), image("two.jpg", 100), image("three.jpg", 100)])

      view
      |> submit_form()
      |> assert_save_refused(view)
    end

    test "refuses a file type that isn't accepted", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/products/new")

      upload_images(view, [%{name: "notes.txt", content: "notes", type: "text/plain"}])

      view
      |> submit_form()
      |> assert_save_refused(view)
    end
  end

  defp image(name, size), do: %{name: name, content: :binary.copy("a", size), type: "image/jpeg"}

  defp upload_images(view, files) do
    input = file_input(view, "#resource-form", :images, files)

    for %{name: name} <- files, do: render_upload(input, name)
  end

  defp submit_form(view) do
    # The price is a hidden input that a JS hook fills in, so it's sent as a value of the submit.
    view
    |> form("#resource-form", change: %{name: "Widget", quantity: "5", manufacturer: "https://example.com"})
    |> put_submitter("button[value=save]")
    |> render_submit(%{change: %{price: "12.34"}})
  end

  defp assert_save_refused(html, view) do
    assert html =~ "remove the files that can&#39;t be uploaded"
    assert Process.alive?(view.pid)
    assert Repo.all(Product) == []
  end
end
