defmodule DemoWeb.Router do
  use DemoWeb, :router

  import Backpex.Router
  import Phoenix.LiveDashboard.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, {DemoWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/" do
    pipe_through :browser
  end

  scope "/", DemoWeb do
    pipe_through :browser

    live "/", HomeLive.Index, :index
  end

  scope "/phoenix_live_dashboard", DemoWeb do
    pipe_through [:browser, DemoWeb.DashboardAuthPlug]

    live_dashboard "/",
      ecto_repos: [Demo.Repo],
      metrics: DemoWeb.Telemetry,
      metrics_history: {DemoWeb.MetricsStorage, :metrics_history, []}
  end

  scope "/admin", DemoWeb do
    pipe_through :browser

    backpex_routes()

    live_session :default, on_mount: Backpex.InitAssigns do
      live_resources "/users", UserLive
      live_resources "/products", ProductLive
      live_resources "/invoices", InvoiceLive, only: [:index]
      live_resources "/posts", PostLive
      live_resources "/categories", CategoryLive
      live_resources "/tags", TagLive
      live_resources "/addresses", AddressLive
      live_resources "/film-reviews", FilmReviewLive
    end
  end
end
