defmodule DemoWeb.Live.Product.EditLiveTest do
  use DemoWeb.ConnCase, async: false

  import Demo.EctoFactory
  import Phoenix.LiveViewTest

  alias Demo.Product
  alias Demo.Repo

  describe "products live resource edit" do
    test "is rendered", %{conn: conn} do
      product = insert(:product)

      conn
      |> visit(~p"/admin/products/#{product.id}/edit")
      |> assert_has("h1", text: "Edit Product", exact: true)
      |> assert_has("button", text: "Cancel", exact: true)
      |> assert_has("button", text: "Save", exact: true)
    end

    test "submit form", %{conn: conn} do
      product =
        insert(:product, %{
          name: "Old Widget",
          quantity: 50,
          manufacturer: "https://example.com",
          price: Money.new(1000, :USD)
        })

      conn
      |> visit(~p"/admin/products/#{product.id}/edit")
      |> unwrap(fn view ->
        view
        |> form("#resource-form",
          change: %{name: "New Widget", quantity: "100"}
        )
        |> put_submitter("button[value=save]")
        |> render_submit()
      end)
      |> assert_has("table tbody tr", count: 1)
      |> assert_has("p", text: "New Widget", exact: true)
    end

    test "editing with invalid data shows error", %{conn: conn} do
      product =
        insert(:product, %{
          name: "Widget",
          quantity: 50,
          manufacturer: "https://example.com",
          price: Money.new(1000, :USD)
        })

      conn
      |> visit(~p"/admin/products/#{product.id}/edit")
      |> unwrap(fn view ->
        view
        |> form("#resource-form", change: %{name: ""})
        |> put_submitter("button[value=save]")
        |> render_submit()
      end)
      |> assert_has("form#resource-form")
      |> assert_has("p", text: "can't be blank")
    end
  end

  # The browser doesn't submit a form while a file input has refused files, but a save event can still reach the server.
  describe "saving while an upload has refused files" do
    setup do
      product = insert(:product, name: "Widget", images: ["old.jpg"], suppliers: [], short_links: [])

      %{product: product}
    end

    test "refuses a file that's too large", %{conn: conn, product: product} do
      {:ok, view, _html} = live(conn, ~p"/admin/products/#{product.id}/edit")

      upload_images(view, [image("big.jpg", 600_000)])

      view
      |> form("#resource-form", change: %{name: "New Widget"})
      |> put_submitter("button[value=save]")
      |> render_submit()
      |> assert_save_refused(view, product)
    end

    test "refuses too many files", %{conn: conn, product: product} do
      {:ok, view, _html} = live(conn, ~p"/admin/products/#{product.id}/edit")

      upload_images(view, [image("one.jpg", 100), image("two.jpg", 100), image("three.jpg", 100)])

      view
      |> form("#resource-form", change: %{name: "New Widget"})
      |> put_submitter("button[value=save]")
      |> render_submit()
      |> assert_save_refused(view, product)
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

  describe "replacing a file" do
    setup :store_uploads_in_tmp_dir
    setup %{upload_root: root}, do: %{images_dir: Path.join(root, "uploads/product/images")}

    setup %{images_dir: images_dir} do
      images_dir
      |> Path.join("old.jpg")
      |> File.write!("old")

      product = insert(:product, name: "Widget", images: ["old.jpg"], suppliers: [], short_links: [])

      %{product: product}
    end

    test "stores the new file and removes the old one", %{conn: conn, product: product, images_dir: images_dir} do
      {:ok, view, _html} = live(conn, ~p"/admin/products/#{product.id}/edit")

      replace_image(view)
      submit_form(view)

      assert %Product{images: [file]} = Repo.get!(Product, product.id)
      assert File.ls!(images_dir) == [file]
    end

    @tag :capture_log
    test "keeps the old file when the new one can't be stored", %{
      conn: conn,
      product: product,
      upload_root: root,
      images_dir: images_dir
    } do
      {:ok, view, _html} = live(conn, ~p"/admin/products/#{product.id}/edit")

      replace_image(view)

      # A file in place of the upload directory makes every write fail. The directory with the old file is set aside.
      File.rename!(root, root <> ".kept")
      File.write!(root, "")

      submit_form(view)

      assert has_element?(view, "#images-drop-target + section > p", "file could not be stored")
      assert %Product{name: "Widget", images: ["old.jpg"]} = Repo.get!(Product, product.id)

      File.rm!(root)
      File.rename!(root <> ".kept", root)

      assert File.ls!(images_dir) == ["old.jpg"]

      # The entry is still in the form, so saving again stores it and removes the old file.
      submit_form(view)

      assert %Product{name: "New Widget", images: [file]} = Repo.get!(Product, product.id)
      assert File.ls!(images_dir) == [file]
    end
  end

  defp replace_image(view) do
    view
    |> element("button[phx-click=cancel-existing-entry][phx-value-ref='old.jpg']")
    |> render_click()

    upload_images(view, [image("new.jpg", 100)])
  end

  defp submit_form(view) do
    view
    |> form("#resource-form", change: %{name: "New Widget"})
    |> put_submitter("button[value=save]")
    |> render_submit()
  end

  defp image(name, size), do: %{name: name, content: :binary.copy("a", size), type: "image/jpeg"}

  defp upload_images(view, files) do
    input = file_input(view, "#resource-form", :images, files)

    for %{name: name} <- files, do: render_upload(input, name)
  end

  defp assert_save_refused(_html, view, product) do
    # The field renders its errors in the section next to its drop target.
    assert has_element?(view, "#images-drop-target + section > p", "remove the files that can't be uploaded")
    assert %Product{name: "Widget", images: ["old.jpg"]} = Repo.get!(Product, product.id)
  end
end
