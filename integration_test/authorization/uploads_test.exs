defmodule Backpex.Integration.Authorization.UploadsTest do
  @moduledoc """
  Checks that removing existing uploads only ever hands `remove_uploads/3` files the item has.
  """
  # The tests write files to the upload directory of the test app.
  use Backpex.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup do
    static_dir = Backpex.Test.Uploads.dir()
    upload_dir = Path.join([static_dir, "uploads", "product", "images"])
    File.mkdir_p!(upload_dir)

    own_file = "own-#{System.unique_integer([:positive])}.jpg"
    foreign_file = "foreign-#{System.unique_integer([:positive])}.jpg"
    # Sits outside the upload directory, reachable only through a path traversal.
    canary_file = "canary-#{System.unique_integer([:positive])}.txt"

    paths = %{
      own: Path.join(upload_dir, own_file),
      foreign: Path.join(upload_dir, foreign_file),
      canary: Path.join(static_dir, canary_file)
    }

    for {_key, path} <- paths, do: File.write!(path, "")
    on_exit(fn -> for {_key, path} <- paths, do: File.rm(path) end)

    product = insert(:product, %{images: [own_file]})
    insert(:product, %{images: [foreign_file]})

    %{product: product, own_file: own_file, foreign_file: foreign_file, canary_file: canary_file, paths: paths}
  end

  test "removes a file the item has", %{conn: conn, product: product, own_file: own_file, paths: paths} do
    {:ok, view, _html} = live(conn, ~p"/admin/products/#{product.id}/edit")

    view
    |> element("button[phx-click='cancel-existing-entry'][phx-value-ref='#{own_file}']")
    |> render_click()

    save_product_form(view)

    refute File.exists?(paths.own)
    assert Repo.reload!(product).images == []
  end

  test "a forged file key never reaches remove_uploads/3", %{
    conn: conn,
    product: product,
    own_file: own_file,
    foreign_file: foreign_file,
    canary_file: canary_file,
    paths: paths
  } do
    {:ok, view, _html} = live(conn, ~p"/admin/products/#{product.id}/edit")

    for ref <- [foreign_file, "../../../#{canary_file}"] do
      view
      |> with_target("#form-component")
      |> render_click("cancel-existing-entry", %{"ref" => ref, "id" => "images"})
    end

    save_product_form(view)

    assert File.exists?(paths.foreign)
    assert File.exists?(paths.canary)
    assert File.exists?(paths.own)
    assert Repo.reload!(product).images == [own_file]
  end

  test "an unknown upload key is ignored", %{conn: conn, product: product, own_file: own_file} do
    {:ok, view, _html} = live(conn, ~p"/admin/products/#{product.id}/edit")

    view
    |> with_target("#form-component")
    |> render_click("cancel-existing-entry", %{"ref" => own_file, "id" => "no_such_upload_key"})

    assert has_element?(view, "button[phx-click='cancel-existing-entry'][phx-value-ref='#{own_file}']")
  end

  defp save_product_form(view) do
    view
    |> form("#resource-form")
    |> put_submitter("button[value=save]")
    |> render_submit()
  end
end
