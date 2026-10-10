defmodule Backpex.ItemActions.DeleteTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Backpex.ItemActions.Delete
  alias Backpex.Test.StubAdapter
  alias Phoenix.LiveView.Socket

  defmodule PostLive do
    @moduledoc false
    def config(:adapter), do: StubAdapter
    def config(:primary_key), do: :id
    def singular_name, do: "Post"
    def plural_name, do: "Posts"

    def translate({msg, opts}) do
      Enum.reduce(opts, msg, fn {key, value}, acc -> String.replace(acc, "%{#{key}}", to_string(value)) end)
    end
  end

  describe "handle/3" do
    test "tells that the items are used elsewhere when the adapter reports a foreign key violation" do
      socket = %Socket{assigns: %{__changed__: %{}, flash: %{}, live_resource: PostLive}}

      {result, log} = with_log(fn -> Delete.handle(socket, [%{id: 1, referenced?: true}], %{}) end)

      assert {:ok, %Socket{assigns: %{flash: %{"error" => message}}}} = result
      assert message == "An error occurred while deleting the Post! The item is used elsewhere."
      assert log =~ ":foreign_key_violation"

      {result, _log} = with_log(fn -> Delete.handle(socket, [%{id: 1, referenced?: true}, %{id: 2}], %{}) end)

      assert {:ok, %Socket{assigns: %{flash: %{"error" => message}}}} = result
      assert message == "An error occurred while deleting 2 Posts! The items are used elsewhere."
    end
  end
end
