defmodule Backpex.ItemActionTest do
  # Unloads a module, so it must not run alongside tests that use it.
  use ExUnit.Case, async: false

  alias Backpex.ItemAction
  alias Backpex.ItemActions.Delete

  describe "has_confirm_modal?/1" do
    test "detects confirm/1 on a module that is not loaded yet" do
      :code.purge(Delete)
      :code.delete(Delete)
      :code.purge(Delete)
      refute :code.is_loaded(Delete)

      assert ItemAction.has_confirm_modal?(%{module: Delete})
    end
  end
end
