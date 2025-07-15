defmodule Backpex.RouterTest do
  use ExUnit.Case, async: true

  describe "live_resources/3 macro" do
    defmodule UserLive do
      def resource_actions, do: []
    end

    defmodule PostLive do
      def resource_actions, do: []
    end

    defmodule CommentLive do
      def resource_actions, do: []
    end

    defmodule ProductLive do
      def resource_actions, do: []
    end

    defmodule TestRouter do
      use Phoenix.Router, helpers: false

      import Phoenix.LiveView.Router
      import Backpex.Router

      # Basic route with defaults
      live_resources "/users", UserLive

      # Route with only option
      live_resources "/posts", PostLive, only: [:index, :show]

      # Route with except option
      live_resources "/comments", CommentLive, except: [:new, :edit]

      # Route with LiveView options
      live_resources "/products", ProductLive,
        container: {:div, class: "container"},
        as: :product,
        metadata: %{section: :catalog},
        private: %{access: :admin}
    end

    test "generates routes with default options" do
      routes = TestRouter.__routes__()

      user_routes = Enum.filter(routes, &(&1.path =~ "/users"))

      assert Enum.any?(user_routes, &(&1.path == "/users"))
      assert Enum.any?(user_routes, &(&1.path == "/users/new"))
      assert Enum.any?(user_routes, &(&1.path == "/users/:backpex_id/edit"))
      assert Enum.any?(user_routes, &(&1.path == "/users/:backpex_id/show"))
    end

    test "respects the only option" do
      routes = TestRouter.__routes__()

      post_routes = Enum.filter(routes, &(&1.path =~ "/posts"))

      assert Enum.any?(post_routes, &(&1.path == "/posts"))
      assert Enum.any?(post_routes, &(&1.path == "/posts/:backpex_id/show"))
      refute Enum.any?(post_routes, &(&1.path == "/posts/new"))
      refute Enum.any?(post_routes, &(&1.path == "/posts/:backpex_id/edit"))
    end

    test "respects the except option" do
      routes = TestRouter.__routes__()

      comment_routes = Enum.filter(routes, &(&1.path =~ "/comments"))

      assert Enum.any?(comment_routes, &(&1.path == "/comments"))
      assert Enum.any?(comment_routes, &(&1.path == "/comments/:backpex_id/show"))
      refute Enum.any?(comment_routes, &(&1.path == "/comments/new"))
      refute Enum.any?(comment_routes, &(&1.path == "/comments/:backpex_id/edit"))
    end

    test "passes LiveView options correctly" do
      routes = TestRouter.__routes__()

      product_route = Enum.find(routes, &(&1.path == "/products"))

      assert product_route.metadata.section == :catalog
    end
  end

  describe "live_resources/3 with NimbleOptions validation" do
    defmodule BadLive do
      def resource_actions, do: []
    end

    defmodule ValidLive do
      def resource_actions, do: []
    end

    test "raises error for invalid option type" do
      assert_raise NimbleOptions.ValidationError, fn ->
        defmodule InvalidRouter1 do
          use Phoenix.Router, helpers: false

          import Phoenix.LiveView.Router
          import Backpex.Router

          # Pass a string to only, which should be a list of atoms
          live_resources "/bad", BadLive, only: "index"
        end
      end
    end

    test "raises error for unknown option" do
      assert_raise NimbleOptions.ValidationError, fn ->
        defmodule InvalidRouter2 do
          use Phoenix.Router, helpers: false

          import Phoenix.LiveView.Router
          import Backpex.Router

          # Pass an unknown option
          live_resources "/bad", BadLive, unknown_option: true
        end
      end
    end

    test "validates container option" do
      defmodule ValidContainerRouter do
        use Phoenix.Router, helpers: false

        import Phoenix.LiveView.Router
        import Backpex.Router

        live_resources "/valid", ValidLive, container: {:div, class: "valid"}
      end
    end

    test "validates metadata and private options" do
      assert_raise NimbleOptions.ValidationError, fn ->
        defmodule InvalidRouter3 do
          use Phoenix.Router, helpers: false

          import Phoenix.LiveView.Router
          import Backpex.Router

          live_resources "/bad", BadLive, metadata: "not a map"
        end
      end

      assert_raise NimbleOptions.ValidationError, fn ->
        defmodule InvalidRouter4 do
          use Phoenix.Router, helpers: false

          import Phoenix.LiveView.Router
          import Backpex.Router

          live_resources "/bad", BadLive, private: [:not, :a, :map]
        end
      end
    end
  end

  describe "backpex_routes/0" do
    defmodule CookieRouter do
      use Phoenix.Router, helpers: false

      import Backpex.Router, only: [backpex_routes: 0]

      scope "/", Test do
        backpex_routes()
      end
    end

    test "defines the cookie controller route" do
      routes = CookieRouter.__routes__()

      cookie_route =
        Enum.find(routes, fn route ->
          route.path == "/backpex_cookies" && route.verb == :post
        end)

      assert cookie_route != nil
      assert cookie_route.plug == Backpex.CookieController
      assert cookie_route.plug_opts == :update

      backpex_routes =
        Enum.filter(routes, fn route ->
          String.starts_with?(route.path, "/backpex")
        end)

      assert length(backpex_routes) == 1
    end
  end
end
