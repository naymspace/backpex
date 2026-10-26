defmodule Backpex.Test.Router do
  @moduledoc """
  The router of the test app. It mounts every fixture LiveResource under `/admin`, like the router of a generated app.
  """
  use Phoenix.Router

  import Backpex.Router
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, {Backpex.Test.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/admin" do
    pipe_through :browser

    backpex_routes()

    live_session :default, on_mount: [Backpex.Test.Sandbox, Backpex.InitAssigns] do
      live_resources "/users", Backpex.Test.UserLive
      live_resources "/products", Backpex.Test.ProductLive
      live_resources "/invoices", Backpex.Test.InvoiceLive, only: [:index]
      live_resources "/posts", Backpex.Test.PostLive
      live_resources "/categories", Backpex.Test.CategoryLive
      live_resources "/tags", Backpex.Test.TagLive
      live_resources "/addresses", Backpex.Test.AddressLive
      live_resources "/film-reviews", Backpex.Test.FilmReviewLive
      live_resources "/short-links", Backpex.Test.ShortLinkLive
      live_resources "/samples", Backpex.Test.SampleLive
    end
  end
end
