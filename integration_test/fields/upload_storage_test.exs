defmodule Backpex.Integration.Fields.UploadStorageTest do
  @moduledoc """
  Checks that the form stores the uploaded files before it saves the item, and that a saved item never references a file
  that wasn't stored.
  """
  # The tests list the upload directory of the test app and replace it with a file to make every write fail.
  use Backpex.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Backpex.Test.Product

  setup do
    images_dir = Path.join([Backpex.Test.Uploads.dir(), "uploads", "product", "images"])
    File.mkdir_p!(images_dir)

    %{images_dir: images_dir}
  end

  describe "creating a product" do
    test "stores the files and saves the product", %{conn: conn, images_dir: images_dir} do
      conn
      |> fill_in_new_product()
      |> upload_images([image("small.jpg", 100)])
      |> submit_new_product()

      assert [%Product{images: [file]}] = Repo.all(Product)
      assert stored?(images_dir, file)
    end

    @tag :capture_log
    test "refuses the save when a file can't be stored and stores it on the next save", %{
      conn: conn,
      images_dir: images_dir
    } do
      session =
        conn
        |> fill_in_new_product()
        |> upload_images([image("small.jpg", 100)])

      restore = break_dir(images_dir)

      session
      |> submit_new_product()
      |> assert_has("#images-drop-target + section > p", text: "file could not be stored")

      assert Repo.all(Product) == []

      restore.()

      # The entry is still in the form, so saving again stores it.
      submit_new_product(session)

      assert [%Product{images: [file]}] = Repo.all(Product)
      assert stored?(images_dir, file)
    end

    test "stores nothing while the form is invalid", %{conn: conn, images_dir: images_dir} do
      files = File.ls!(images_dir)

      conn
      |> visit(~p"/admin/products/new")
      |> fill_in("Quantity", with: "5")
      |> fill_in("Manufacturer URL", with: "https://example.com")
      |> upload_images([image("small.jpg", 100)])
      |> submit_new_product()
      |> assert_has("p", text: "can't be blank")

      assert Repo.all(Product) == []
      assert File.ls!(images_dir) == files
    end

    test "discards the stored files when the save fails and stores them again on the next save", %{
      conn: conn,
      images_dir: images_dir
    } do
      insert(:short_link, short_key: "taken")
      files = File.ls!(images_dir)

      session =
        conn
        |> fill_in_new_product()
        |> upload_images([image("small.jpg", 100)])

      # The short key passes the changeset, the primary key of the database refuses it.
      session
      |> submit_new_product(short_link("taken"))
      |> assert_has("p", text: "has already been taken")

      assert Repo.all(Product) == []
      assert File.ls!(images_dir) == files

      submit_new_product(session, short_link("free"))

      assert [%Product{images: [file]}] = Repo.all(Product)
      assert stored?(images_dir, file)
    end
  end

  describe "replacing a file of a product" do
    setup %{images_dir: images_dir} do
      old_file = "old-#{System.unique_integer([:positive])}.jpg"
      old_path = Path.join(images_dir, old_file)
      File.write!(old_path, "old")
      on_exit(fn -> File.rm(old_path) end)

      product = insert(:product, name: "Widget", images: [old_file])

      %{product: product, old_file: old_file, old_path: old_path}
    end

    test "stores the new file and removes the old one", %{
      conn: conn,
      product: product,
      old_file: old_file,
      old_path: old_path,
      images_dir: images_dir
    } do
      conn
      |> replace_image(product, old_file)
      |> send_save()

      assert %Product{name: "New Widget", images: [file]} = Repo.get!(Product, product.id)
      assert stored?(images_dir, file)
      refute File.exists?(old_path)
    end

    @tag :capture_log
    test "keeps the old file when the new one can't be stored", %{
      conn: conn,
      product: product,
      old_file: old_file,
      old_path: old_path,
      images_dir: images_dir
    } do
      session = replace_image(conn, product, old_file)
      files = File.ls!(images_dir)

      restore = break_dir(images_dir)

      session
      |> send_save()
      |> assert_has("#images-drop-target + section > p", text: "file could not be stored")

      assert %Product{name: "Widget", images: [^old_file]} = Repo.get!(Product, product.id)

      restore.()

      assert File.ls!(images_dir) == files

      # The entry is still in the form, so saving again stores it and removes the old file.
      send_save(session)

      assert %Product{name: "New Widget", images: [file]} = Repo.get!(Product, product.id)
      assert stored?(images_dir, file)
      refute File.exists?(old_path)
    end
  end

  # Replaces the directory with a file, so every write into it fails. Returns a function that puts the directory back.
  defp break_dir(dir) do
    kept = dir <> ".kept"
    File.rename!(dir, kept)
    File.write!(dir, "")

    restore = fn ->
      if File.regular?(dir), do: File.rm!(dir)
      if File.dir?(kept), do: File.rename!(kept, dir)
    end

    on_exit(restore)
    restore
  end

  defp stored?(dir, file), do: dir |> Path.join(file) |> File.exists?()

  defp image(name, size), do: %{name: name, content: :binary.copy("a", size), type: "image/jpeg"}

  defp short_link(short_key), do: %{"0" => %{short_key: short_key, url: "https://example.com"}}

  defp fill_in_new_product(conn) do
    conn
    |> visit(~p"/admin/products/new")
    |> fill_in("Name", with: "Widget")
    |> fill_in("Quantity", with: "5")
    |> fill_in("Manufacturer URL", with: "https://example.com")
  end

  defp replace_image(conn, product, old_file) do
    conn
    |> visit(~p"/admin/products/#{product.id}/edit")
    |> fill_in("Name", with: "New Widget")
    |> click_button("Remove #{old_file}")
    |> upload_images([image("new.jpg", 100)])
  end

  # phoenix_test can't keep an upload entry across two saves, so the tests upload with LiveViewTest and send the save
  # event themselves.
  defp upload_images(session, files) do
    unwrap(session, fn view ->
      input = file_input(view, "#resource-form", :images, files)

      for %{name: name} <- files, do: render_upload(input, name)

      render(view)
    end)
  end

  defp submit_new_product(session, short_links \\ nil) do
    # The price is a hidden input that a JS hook fills in, so it's sent as a value of the submit.
    change = if short_links, do: %{price: "12.34", short_links: short_links}, else: %{price: "12.34"}

    send_save(session, %{change: change})
  end

  defp send_save(session, params \\ %{}) do
    unwrap(session, fn view ->
      view
      |> form("#resource-form")
      |> put_submitter("button[value=save]")
      |> render_submit(params)
    end)
  end
end
