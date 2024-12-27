defmodule Backpex.BackpexTextApp.BasicEndToEndTests do
  use BackpexTestAppWeb.ConnCase
  import PhoenixTest

  test "home page (/) renders correctly", %{conn: conn} do
    conn
    |> visit("/")
    |> assert_has("p", text: "Peace of mind")
  end
end
