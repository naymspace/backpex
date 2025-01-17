defmodule Backpex.Controllers.CookieControllerTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Phoenix.ConnTest

  alias Backpex.CookieController

  setup do
    conn =
      build_conn()
      |> Plug.Test.init_test_session(%{})
      |> fetch_session()

    {:ok, conn: conn}
  end

  describe "update/2 with toggle_columns" do
    test "updates session and redirects", %{conn: conn} do
      params = %{
        "toggle_columns" => %{
          "_cookie_redirect_url" => "/redirect",
          "_resource" => "users",
          "column1" => "true",
          "column2" => "false"
        }
      }

      conn = CookieController.update(conn, params)

      assert redirected_to(conn) == "/redirect"

      assert get_session(conn, "backpex") == %{
               "column_toggle" => %{
                 "users" => %{"column1" => "true", "column2" => "false"}
               }
             }
    end
  end

  describe "update/2 with toggle_metrics" do
    test "toggles metric visibility to false when not set", %{conn: conn} do
      params = %{
        "toggle_metrics" => %{
          "_cookie_redirect_url" => "/redirect",
          "_resource" => "users"
        }
      }

      conn = CookieController.update(conn, params)

      assert redirected_to(conn) == "/redirect"

      assert get_session(conn, "backpex") == %{
               "metric_visibility" => %{"users" => false}
             }
    end

    test "toggles metric visibility to true when already set to false", %{conn: conn} do
      conn = put_session(conn, "backpex", %{"metric_visibility" => %{"users" => false}})

      params = %{
        "toggle_metrics" => %{
          "_cookie_redirect_url" => "/redirect",
          "_resource" => "users"
        }
      }

      conn = CookieController.update(conn, params)

      assert redirected_to(conn) == "/redirect"

      assert get_session(conn, "backpex") == %{
               "metric_visibility" => %{"users" => true}
             }
    end
  end

  describe "update/2 with select_theme" do
    test "updates theme in session", %{conn: conn} do
      params = %{"select_theme" => "dark"}

      conn = CookieController.update(conn, params)

      assert json_response(conn, 200) == %{}
      assert get_session(conn, "backpex") == %{"theme" => "dark"}
    end
  end
end
