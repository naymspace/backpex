defmodule DemoWeb.Live.Product.NewLiveTest do
  use DemoWeb.ConnCase, async: false

  import Demo.EctoFactory
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

  describe "storing the files before the product is saved" do
    setup :store_uploads_in_tmp_dir
    setup %{upload_root: root}, do: %{images_dir: Path.join(root, "uploads/product/images")}

    test "stores the files and saves the product", %{conn: conn, images_dir: images_dir} do
      {:ok, view, _html} = live(conn, ~p"/admin/products/new")

      upload_images(view, [image("small.jpg", 100)])
      submit_form(view)

      assert [%Product{images: [file]}] = Repo.all(Product)
      assert File.ls!(images_dir) == [file]
    end

    @tag :capture_log
    test "refuses the save when a file can't be stored and stores it on the next save", %{
      conn: conn,
      upload_root: root,
      images_dir: images_dir
    } do
      # A file in place of the upload directory makes every write fail.
      File.rm_rf!(root)
      File.write!(root, "")

      {:ok, view, _html} = live(conn, ~p"/admin/products/new")

      upload_images(view, [image("small.jpg", 100)])
      submit_form(view)

      assert has_element?(view, "#images-drop-target + section > p", "file could not be stored")
      assert Repo.all(Product) == []

      File.rm!(root)
      File.mkdir_p!(images_dir)

      # The entry is still in the form, so saving again stores it.
      submit_form(view)

      assert [%Product{images: [file]}] = Repo.all(Product)
      assert File.ls!(images_dir) == [file]
    end

    test "stores nothing while the form is invalid", %{conn: conn, images_dir: images_dir} do
      {:ok, view, _html} = live(conn, ~p"/admin/products/new")

      upload_images(view, [image("small.jpg", 100)])

      html =
        view
        |> form("#resource-form", change: %{quantity: "5", manufacturer: "https://example.com"})
        |> put_submitter("button[value=save]")
        |> render_submit(%{change: %{price: "12.34"}})

      assert html =~ "can&#39;t be blank"
      assert Repo.all(Product) == []
      assert File.ls!(images_dir) == []
    end

    test "discards the stored files when the save fails and stores them again on the next save", %{
      conn: conn,
      images_dir: images_dir
    } do
      insert(:short_link, short_key: "taken")

      {:ok, view, _html} = live(conn, ~p"/admin/products/new")

      upload_images(view, [image("small.jpg", 100)])

      # The short key passes the changeset, the unique constraint of the database refuses it.
      html = submit_form_with_short_link(view, "taken")

      assert html =~ "has already been taken"
      assert Repo.all(Product) == []
      assert File.ls!(images_dir) == []

      submit_form_with_short_link(view, "free")

      assert [%Product{images: [file]}] = Repo.all(Product)
      assert File.ls!(images_dir) == [file]
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

  defp submit_form_with_short_link(view, short_key) do
    short_links = %{"0" => %{short_key: short_key, url: "https://example.com"}}

    view
    |> form("#resource-form", change: %{name: "Widget", quantity: "5", manufacturer: "https://example.com"})
    |> put_submitter("button[value=save]")
    |> render_submit(%{change: %{price: "12.34", short_links: short_links}})
  end

  defp assert_save_refused(_html, view) do
    # The field renders its errors in the section next to its drop target.
    assert has_element?(view, "#images-drop-target + section > p", "remove the files that can't be uploaded")
    assert Repo.all(Product) == []
  end
end
