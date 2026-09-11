defmodule Backpex.AuthorizationTest do
  use ExUnit.Case, async: true

  alias Backpex.Authorization
  alias Backpex.Test.LiveResources.AllowAll
  alias Backpex.Test.LiveResources.DenyAll
  alias Backpex.Test.LiveResources.KeyAware
  alias Backpex.Test.LiveResources.Recording
  alias Phoenix.LiveView.Socket

  @assigns %{live_resource: AllowAll}

  describe "can?/4" do
    test "delegates to the live resource" do
      assert Authorization.can?(AllowAll, @assigns, :new, nil)
      refute Authorization.can?(DenyAll, @assigns, :new, nil)
    end

    test "passes action and item through untouched" do
      item = %{id: 1}

      assert Authorization.can?(Recording, @assigns, :edit, item)
      assert_received {:can?, :edit, ^item}
    end

    test "supports a nil item" do
      refute Authorization.can?(KeyAware, @assigns, :new, nil)
      assert Authorization.can?(KeyAware, @assigns, :edit, nil)
    end

    test "refuses a socket where assigns are expected" do
      # Authorizing against a `%Phoenix.LiveView.Socket{}` would answer for the wrong context. The
      # guard has to reject it loudly instead of handing the struct to `can?/3`.
      args = [AllowAll, %Socket{}, :new, nil]

      assert_raise FunctionClauseError, fn ->
        apply(Authorization, :can?, args)
      end
    end
  end

  describe "can_all?/4" do
    test "returns true when every item is authorized" do
      assert Authorization.can_all?(KeyAware, @assigns, :delete, [%{role: :user}, %{role: :user}])
    end

    test "returns false when a single item is unauthorized" do
      refute Authorization.can_all?(KeyAware, @assigns, :delete, [%{role: :user}, %{role: :admin}])
    end

    test "returns true for an empty list" do
      assert Authorization.can_all?(DenyAll, @assigns, :delete, [])
    end
  end

  describe "authorize!/4" do
    test "returns :ok when authorized" do
      assert :ok = Authorization.authorize!(AllowAll, @assigns, :new, nil)
    end

    test "raises ForbiddenError when not authorized" do
      assert_raise Backpex.ForbiddenError, fn ->
        Authorization.authorize!(DenyAll, @assigns, :new, nil)
      end
    end

    test "does not treat a nil item as a missing record" do
      assert :ok = Authorization.authorize!(AllowAll, @assigns, :new, nil)
    end
  end

  describe "authorize_all!/4" do
    test "returns :ok when every item is authorized" do
      assert :ok = Authorization.authorize_all!(KeyAware, @assigns, :delete, [%{role: :user}])
    end

    test "raises ForbiddenError when a single item is unauthorized" do
      assert_raise Backpex.ForbiddenError, fn ->
        Authorization.authorize_all!(KeyAware, @assigns, :delete, [%{role: :user}, %{role: :admin}])
      end
    end

    test "raises NoResultsError when the list contains nil" do
      assert_raise Backpex.NoResultsError, fn ->
        Authorization.authorize_all!(AllowAll, @assigns, :delete, [%{role: :user}, nil])
      end
    end

    test "never passes nil to the live resource" do
      assert_raise Backpex.NoResultsError, fn ->
        Authorization.authorize_all!(Recording, @assigns, :delete, [nil])
      end

      refute_received {:can?, :delete, nil}
    end

    test "returns :ok for an empty list" do
      assert :ok = Authorization.authorize_all!(DenyAll, @assigns, :delete, [])
    end
  end
end
