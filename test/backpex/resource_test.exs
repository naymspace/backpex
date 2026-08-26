defmodule Backpex.ResourceTest do
  use ExUnit.Case, async: true

  alias Backpex.Resource
  alias Backpex.Test.LiveResources
  alias Backpex.Test.LiveResources.AllowAll
  alias Backpex.Test.LiveResources.DenyAll
  alias Backpex.Test.LiveResources.NoAdmins
  alias Backpex.Test.LiveResources.OnlyCustomKey
  alias Backpex.Test.LiveResources.Recording

  setup do
    start_supervised!({Phoenix.PubSub, name: LiveResources.pubsub_server()})
    :ok = Phoenix.PubSub.subscribe(LiveResources.pubsub_server(), LiveResources.pubsub_topic())

    %{assigns: %{some: :assign}, item: %{id: 1}, fields: []}
  end

  describe "insert/6" do
    test "authorizes :new with a nil item before building the changeset", %{assigns: assigns, item: item, fields: f} do
      assert {:ok, ^item} = Resource.insert(item, %{}, f, assigns, Recording)

      assert_received {:can?, :new, nil}
    end

    test "raises before change/6 when not authorized", %{assigns: assigns, item: item, fields: f} do
      assert_raise Backpex.ForbiddenError, fn ->
        Resource.insert(item, %{}, f, assigns, DenyAll)
      end

      refute_received {:adapter, :change, _opts}
      refute_received {:adapter, :insert, _item, _attrs}
    end

    test "broadcasts on success", %{assigns: assigns, item: item, fields: f} do
      assert {:ok, ^item} = Resource.insert(item, %{}, f, assigns, AllowAll)

      assert_received {"created", ^item}
      assert_received {"backpex:created", ^item}
    end

    test "honors :authorization_action", %{assigns: assigns, item: item, fields: f} do
      assert_raise Backpex.ForbiddenError, fn ->
        Resource.insert(item, %{}, f, assigns, OnlyCustomKey)
      end

      assert {:ok, ^item} =
               Resource.insert(item, %{}, f, assigns, OnlyCustomKey, authorization_action: :custom_key)
    end

    test "honors authorize?: false", %{assigns: assigns, item: item, fields: f} do
      assert {:ok, ^item} = Resource.insert(item, %{}, f, assigns, DenyAll, authorize?: false)

      assert_received {:adapter, :insert, ^item, _attrs}
    end

    test "does not leak authorization options into change/6", %{assigns: assigns, item: item, fields: f} do
      opts = [authorization_action: :custom_key, authorize?: true, assocs: [tags: []]]

      assert {:ok, ^item} = Resource.insert(item, %{}, f, assigns, OnlyCustomKey, opts)

      assert_received {:adapter, :change, change_opts}
      refute Keyword.has_key?(change_opts, :authorization_action)
      refute Keyword.has_key?(change_opts, :authorize?)
      assert Keyword.get(change_opts, :assocs) == [tags: []]
      assert Keyword.get(change_opts, :action) == :insert
    end

    test "raises when :authorize? is not a boolean", %{assigns: assigns, item: item, fields: f} do
      assert_raise ArgumentError, fn ->
        Resource.insert(item, %{}, f, assigns, AllowAll, authorize?: :nope)
      end
    end
  end

  describe "update/6" do
    test "authorizes :edit with the item", %{assigns: assigns, item: item, fields: f} do
      assert {:ok, ^item} = Resource.update(item, %{}, f, assigns, Recording)

      assert_received {:can?, :edit, ^item}
    end

    test "raises before change/6 when not authorized", %{assigns: assigns, item: item, fields: f} do
      assert_raise Backpex.ForbiddenError, fn ->
        Resource.update(item, %{}, f, assigns, DenyAll)
      end

      refute_received {:adapter, :change, _opts}
      refute_received {:adapter, :update, _item, _attrs}
    end

    test "broadcasts on success", %{assigns: assigns, item: item, fields: f} do
      assert {:ok, ^item} = Resource.update(item, %{}, f, assigns, AllowAll)

      assert_received {"updated", ^item}
      assert_received {"backpex:updated", ^item}
    end

    test "honors :authorization_action and authorize?: false", %{assigns: assigns, item: item, fields: f} do
      assert {:ok, ^item} =
               Resource.update(item, %{}, f, assigns, OnlyCustomKey, authorization_action: :custom_key)

      assert {:ok, ^item} = Resource.update(item, %{}, f, assigns, DenyAll, authorize?: false)
    end
  end

  describe "delete_all/4" do
    test "authorizes :delete per item", %{assigns: assigns} do
      items = [%{id: 1}, %{id: 2}]

      assert {:ok, ^items} = Resource.delete_all(items, assigns, Recording)

      assert_received {:can?, :delete, %{id: 1}}
      assert_received {:can?, :delete, %{id: 2}}
    end

    test "raises for the whole call when a single item is unauthorized", %{assigns: assigns} do
      items = [%{id: 1, role: :user}, %{id: 2, role: :admin}]

      assert_raise Backpex.ForbiddenError, fn ->
        Resource.delete_all(items, assigns, NoAdmins)
      end

      refute_received {:adapter, :delete_all, _items}
    end

    test "raises NoResultsError when the list contains nil", %{assigns: assigns} do
      assert_raise Backpex.NoResultsError, fn ->
        Resource.delete_all([%{id: 1}, nil], assigns, AllowAll)
      end

      refute_received {:adapter, :delete_all, _items}
    end

    test "passes an empty list vacuously", %{assigns: assigns} do
      assert {:ok, []} = Resource.delete_all([], assigns, DenyAll)

      assert_received {:adapter, :delete_all, []}
    end

    test "honors :authorization_action and authorize?: false", %{assigns: assigns} do
      items = [%{id: 1}]

      assert {:ok, ^items} = Resource.delete_all(items, assigns, OnlyCustomKey, authorization_action: :custom_key)
      assert {:ok, ^items} = Resource.delete_all(items, assigns, DenyAll, authorize?: false)
    end

    test "broadcasts a deleted event per item", %{assigns: assigns} do
      item = %{id: 1}

      assert {:ok, _items} = Resource.delete_all([item], assigns, AllowAll)

      assert_received {"deleted", ^item}
      assert_received {"backpex:deleted", ^item}
    end

    test "does not answer the pre-0.21 delete_all/2 signature" do
      # The arguments go through a variable so the compiler's type checker does not flag the
      # intentionally wrong call — what is under test is the runtime behavior.
      args = [[%{id: 1}], AllowAll]

      assert_raise UndefinedFunctionError, fn ->
        apply(Resource, :delete_all, args)
      end
    end
  end

  describe "update_all/5" do
    test "authorizes :edit per item", %{assigns: assigns} do
      items = [%{id: 1}, %{id: 2}]

      assert {:ok, ^items} = Resource.update_all(items, [set: [x: 1]], assigns, Recording)

      assert_received {:can?, :edit, %{id: 1}}
      assert_received {:can?, :edit, %{id: 2}}
    end

    test "raises for the whole call when a single item is unauthorized", %{assigns: assigns} do
      items = [%{id: 1, role: :user}, %{id: 2, role: :admin}]

      assert_raise Backpex.ForbiddenError, fn ->
        Resource.update_all(items, [set: [x: 1]], assigns, NoAdmins)
      end

      refute_received {:adapter, :update_all, _items, _updates}
    end

    test "raises NoResultsError when the list contains nil", %{assigns: assigns} do
      assert_raise Backpex.NoResultsError, fn ->
        Resource.update_all([%{id: 1}, nil], [set: [x: 1]], assigns, AllowAll)
      end

      refute_received {:adapter, :update_all, _items, _updates}
    end

    test "passes an empty list vacuously", %{assigns: assigns} do
      assert {:ok, []} = Resource.update_all([], [set: [x: 1]], assigns, DenyAll)
    end

    test "broadcasts the default event", %{assigns: assigns} do
      item = %{id: 1}

      assert {:ok, _items} = Resource.update_all([item], [set: [x: 1]], assigns, AllowAll)

      assert_received {"updated", ^item}
      assert_received {"backpex:updated", ^item}
    end

    test "honors :event_name", %{assigns: assigns} do
      item = %{id: 1}

      assert {:ok, _items} = Resource.update_all([item], [set: [x: 1]], assigns, AllowAll, event_name: "deleted")

      assert_received {"deleted", ^item}
      assert_received {"backpex:deleted", ^item}
    end

    test "honors :authorization_action and authorize?: false", %{assigns: assigns} do
      items = [%{id: 1}]

      assert {:ok, ^items} =
               Resource.update_all(items, [set: [x: 1]], assigns, OnlyCustomKey, authorization_action: :custom_key)

      assert {:ok, ^items} = Resource.update_all(items, [set: [x: 1]], assigns, DenyAll, authorize?: false)
    end

    test "raises FunctionClauseError for the pre-0.21 update_all/4 signature", %{assigns: _assigns} do
      # `update_all(items, updates, "deleted", MyLive)` has the same arity as the new
      # `update_all(items, updates, assigns, live_resource)`. The `is_map(assigns)` guard makes the
      # old call fail loudly instead of silently authorizing against a string.
      args = [[%{id: 1}], [set: [x: 1]], "deleted", AllowAll]

      assert_raise FunctionClauseError, fn ->
        apply(Resource, :update_all, args)
      end
    end
  end
end
