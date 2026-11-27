defmodule Backpex.UploadHelpers do
  @moduledoc """
  Fills in and saves the product form of the test app with uploaded images.
  """
  use Phoenix.VerifiedRoutes, endpoint: Backpex.Test.Endpoint, router: Backpex.Test.Router

  import Phoenix.LiveViewTest
  import PhoenixTest

  def image(name, size), do: %{name: name, content: :binary.copy("a", size), type: "image/jpeg"}

  def fill_in_new_product(conn) do
    conn
    |> visit(~p"/admin/products/new")
    |> fill_in("Name", with: "Widget")
    |> fill_in("Quantity", with: "5")
    |> fill_in("Manufacturer URL", with: "https://example.com")
  end

  # phoenix_test can't keep an upload entry across two saves, so the tests upload with LiveViewTest and send the save
  # event themselves.
  def upload_images(session, files) do
    unwrap(session, fn view ->
      input = file_input(view, "#resource-form", :images, files)

      for %{name: name} <- files, do: render_upload(input, name)

      render(view)
    end)
  end

  def submit_new_product(session, change \\ %{}) do
    # The price is a hidden input that a JS hook fills in, so it's sent as a value of the submit.
    send_save(session, %{change: Map.put(change, :price, "12.34")})
  end

  def send_save(session, params \\ %{}) do
    unwrap(session, fn view ->
      view
      |> form("#resource-form")
      |> put_submitter("button[value=save]")
      |> render_submit(params)
    end)
  end
end
