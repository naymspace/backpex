defmodule Backpex.Integration.Fields.UploadTest do
  use Backpex.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Backpex.Test.Product

  # The browser doesn't submit a form while a file input has refused files, but a save event can still reach the server.
  # phoenix_test raises on a refused file, so the tests upload with LiveViewTest and send the save event themselves.
  describe "creating an item while the upload has refused files" do
    test "refuses a file that's too large next to a valid one", %{conn: conn} do
      conn
      |> fill_in_new_product()
      |> upload_images([image("small.jpg", 100), image("big.jpg", 600_000)])
      |> submit_new_product()
      |> assert_new_product_refused()
    end

    test "refuses too many files", %{conn: conn} do
      conn
      |> fill_in_new_product()
      |> upload_images([image("one.jpg", 100), image("two.jpg", 100), image("three.jpg", 100)])
      |> submit_new_product()
      |> assert_new_product_refused()
    end

    test "refuses a file type that isn't accepted", %{conn: conn} do
      conn
      |> fill_in_new_product()
      |> upload_images([%{name: "notes.txt", content: "notes", type: "text/plain"}])
      |> submit_new_product()
      |> assert_new_product_refused()
    end
  end

  describe "updating an item while the upload has refused files" do
    setup do
      %{product: insert(:product, name: "Widget", images: ["old.jpg"])}
    end

    test "refuses a file that's too large", %{conn: conn, product: product} do
      conn
      |> visit(~p"/admin/products/#{product.id}/edit")
      |> fill_in("Name", with: "New Widget")
      |> upload_images([image("big.jpg", 600_000)])
      |> send_save()
      |> assert_update_refused(product)
    end

    test "refuses too many files", %{conn: conn, product: product} do
      conn
      |> visit(~p"/admin/products/#{product.id}/edit")
      |> fill_in("Name", with: "New Widget")
      |> upload_images([image("one.jpg", 100), image("two.jpg", 100), image("three.jpg", 100)])
      |> send_save()
      |> assert_update_refused(product)
    end

    test "refuses a save event without a save type", %{conn: conn, product: product} do
      conn
      |> visit(~p"/admin/products/#{product.id}/edit")
      |> upload_images([%{name: "notes.txt", content: "notes", type: "text/plain"}])
      # Without a submitter, the event has no save type. That clause ignores the form params.
      |> unwrap(fn view -> view |> form("#resource-form") |> render_submit() end)
      |> assert_has("#images-drop-target + section > p", text: "remove the files that can't be uploaded")

      assert %Product{images: ["old.jpg"]} = Repo.get!(Product, product.id)
    end
  end

  defp image(name, size), do: %{name: name, content: :binary.copy("a", size), type: "image/jpeg"}

  defp fill_in_new_product(conn) do
    conn
    |> visit(~p"/admin/products/new")
    |> fill_in("Name", with: "Widget")
    |> fill_in("Quantity", with: "5")
    |> fill_in("Manufacturer URL", with: "https://example.com")
  end

  defp upload_images(session, files) do
    unwrap(session, fn view ->
      input = file_input(view, "#resource-form", :images, files)

      for %{name: name} <- files, do: render_upload(input, name)

      render(view)
    end)
  end

  defp submit_new_product(session) do
    # The price is a hidden input that a JS hook fills in, so it's sent as a value of the submit.
    send_save(session, %{change: %{price: "12.34"}})
  end

  defp send_save(session, params \\ %{}) do
    unwrap(session, fn view ->
      view
      |> form("#resource-form")
      |> put_submitter("button[value=save]")
      |> render_submit(params)
    end)
  end

  # The field renders its errors in the section next to its drop target.
  defp assert_new_product_refused(session) do
    assert_has(session, "#images-drop-target + section > p", text: "remove the files that can't be uploaded")
    assert Repo.all(Product) == []
  end

  defp assert_update_refused(session, product) do
    assert_has(session, "#images-drop-target + section > p", text: "remove the files that can't be uploaded")
    assert %Product{name: "Widget", images: ["old.jpg"]} = Repo.get!(Product, product.id)
  end
end
