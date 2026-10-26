defmodule Backpex.Integration.Fields.UploadTest do
  use Backpex.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Backpex.Test.Product

  # The browser doesn't submit a form while a file input has refused files, but a save event can still reach the server.
  describe "creating an item while the upload has refused files" do
    test "refuses a file that's too large next to a valid one", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/products/new")

      upload_images(view, [image("small.jpg", 100), image("big.jpg", 600_000)])

      submit_new_product(view)
      assert_new_product_refused(view)
    end

    test "refuses too many files", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/products/new")

      upload_images(view, [image("one.jpg", 100), image("two.jpg", 100), image("three.jpg", 100)])

      submit_new_product(view)
      assert_new_product_refused(view)
    end

    test "refuses a file type that isn't accepted", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/products/new")

      upload_images(view, [%{name: "notes.txt", content: "notes", type: "text/plain"}])

      submit_new_product(view)
      assert_new_product_refused(view)
    end
  end

  describe "updating an item while the upload has refused files" do
    setup do
      %{product: insert(:product, name: "Widget", images: ["old.jpg"])}
    end

    test "refuses a file that's too large", %{conn: conn, product: product} do
      {:ok, view, _html} = live(conn, ~p"/admin/products/#{product.id}/edit")

      upload_images(view, [image("big.jpg", 600_000)])

      submit_product_name(view)
      assert_update_refused(view, product)
    end

    test "refuses too many files", %{conn: conn, product: product} do
      {:ok, view, _html} = live(conn, ~p"/admin/products/#{product.id}/edit")

      upload_images(view, [image("one.jpg", 100), image("two.jpg", 100), image("three.jpg", 100)])

      submit_product_name(view)
      assert_update_refused(view, product)
    end

    test "refuses a save event without a save type", %{conn: conn, product: product} do
      {:ok, view, _html} = live(conn, ~p"/admin/products/#{product.id}/edit")

      upload_images(view, [%{name: "notes.txt", content: "notes", type: "text/plain"}])

      # Without a submitter, the event has no save type. That clause ignores the form params.
      view
      |> form("#resource-form")
      |> render_submit()

      assert has_element?(view, "#images-drop-target + section > p", "remove the files that can't be uploaded")
      assert %Product{images: ["old.jpg"]} = Repo.get!(Product, product.id)
    end
  end

  defp image(name, size), do: %{name: name, content: :binary.copy("a", size), type: "image/jpeg"}

  defp upload_images(view, files) do
    input = file_input(view, "#resource-form", :images, files)

    for %{name: name} <- files, do: render_upload(input, name)
  end

  defp submit_new_product(view) do
    # The price is a hidden input that a JS hook fills in, so it's sent as a value of the submit.
    view
    |> form("#resource-form", change: %{name: "Widget", quantity: "5", manufacturer: "https://example.com"})
    |> put_submitter("button[value=save]")
    |> render_submit(%{change: %{price: "12.34"}})
  end

  defp submit_product_name(view) do
    view
    |> form("#resource-form", change: %{name: "New Widget"})
    |> put_submitter("button[value=save]")
    |> render_submit()
  end

  # The field renders its errors in the section next to its drop target.
  defp assert_new_product_refused(view) do
    assert has_element?(view, "#images-drop-target + section > p", "remove the files that can't be uploaded")
    assert Repo.all(Product) == []
  end

  defp assert_update_refused(view, product) do
    assert has_element?(view, "#images-drop-target + section > p", "remove the files that can't be uploaded")
    assert %Product{name: "Widget", images: ["old.jpg"]} = Repo.get!(Product, product.id)
  end
end
