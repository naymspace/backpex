defmodule Backpex.AuthorizationTest do
  use ExUnit.Case, async: true

  alias Backpex.Authorization

  defmodule AllowAll do
    @moduledoc false
    def can?(_assigns, _action, _item), do: true
  end

  defmodule DenyAll do
    @moduledoc false
    def can?(_assigns, _action, _item), do: false
  end

  defmodule KeyAware do
    @moduledoc false
    def can?(_assigns, :delete, %{role: :admin} = _item), do: false
    def can?(_assigns, :delete, _item), do: true
    def can?(_assigns, :new, nil), do: false
    def can?(_assigns, _action, _item), do: true
  end

  defmodule Recorder do
    @moduledoc false
    def can?(assigns, action, item) do
      send(assigns.test_pid, {:can?, action, item})
      true
    end
  end

  @assigns %{live_resource: AllowAll}

  describe "can?/4" do
    test "delegates to the live resource" do
      assert Authorization.can?(AllowAll, @assigns, :new, nil)
      refute Authorization.can?(DenyAll, @assigns, :new, nil)
    end

    test "passes action and item through untouched" do
      item = %{id: 1}

      assert Authorization.can?(Recorder, %{test_pid: self()}, :edit, item)
      assert_received {:can?, :edit, ^item}
    end

    test "supports a nil item" do
      refute Authorization.can?(KeyAware, @assigns, :new, nil)
      assert Authorization.can?(KeyAware, @assigns, :edit, nil)
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
        Authorization.authorize_all!(Recorder, %{test_pid: self()}, :delete, [nil])
      end

      refute_received {:can?, :delete, nil}
    end

    test "returns :ok for an empty list" do
      assert :ok = Authorization.authorize_all!(DenyAll, @assigns, :delete, [])
    end
  end
end
