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
      live_resources "/notes", Backpex.Test.NoteLive
      live_resources "/post-relation-options", Backpex.Test.PostRelationOptionsLive
      live_resources "/scoped-posts", Backpex.Test.ScopedPostLive
      live_resources "/memory-notes", Backpex.Test.MemoryNoteLive
      live_resources "/user-relation-options", Backpex.Test.UserRelationOptionsLive
      live_resources "/sample-field-options", Backpex.Test.SampleFieldOptionsLive
      live_resources "/recording-notes", Backpex.Test.RecordingNoteLive
      live_resources "/paged-notes", Backpex.Test.PagedNoteLive
      live_resources "/pubsub-notes", Backpex.Test.PubSubNoteLive
      live_resources "/order-nulls-default-users", Backpex.Test.OrderNullsDefaultUserLive
      live_resources "/order-nulls-first-users", Backpex.Test.OrderNullsFirstUserLive
      live_resources "/order-nulls-last-users", Backpex.Test.OrderNullsLastUserLive
      live_resources "/order-nulls-smallest-users", Backpex.Test.OrderNullsSmallestUserLive
      live_resources "/field-options-samples", Backpex.Test.FieldOptionsSampleLive
      live_resources "/display-options-samples", Backpex.Test.DisplayOptionsSampleLive
      live_resources "/fluid-notes", Backpex.Test.FluidNoteLive
      live_resources "/on-mount-module-notes", Backpex.Test.OnMountModuleNoteLive
      live_resources "/on-mount-tuple-notes", Backpex.Test.OnMountTupleNoteLive
      live_resources "/on-mount-list-notes", Backpex.Test.OnMountListNoteLive
    end
  end
end
