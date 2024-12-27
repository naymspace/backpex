defmodule BackpexTestAppWeb.Router do
  use BackpexTestAppWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {BackpexTestAppWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", BackpexTestAppWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  import Backpex.Router

  scope "/payroll", BackpexTestAppWeb do
    pipe_through :browser

    backpex_routes()

    live_session :default, on_mount: Backpex.InitAssigns do
      live_resources "/employees", EmployeeLive
      live_resources "/departments", DepartmentLive
      live_resources "/functions", FunctionLive
    end
  end
end
