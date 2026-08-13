defmodule Backpex.Preferences.Adapters.EctoTest do
  use ExUnit.Case, async: true

  alias Backpex.Preferences.Adapters.Ecto, as: EctoAdapter
  alias Backpex.Preferences.Context
  alias Backpex.Test.Preferences.FakeRepo

  defmodule Preference do
    @moduledoc false
    use Ecto.Schema

    schema "backpex_preferences" do
      field :user_id, :integer
      field :tenant_id, :integer
      field :key, :string
      field :value, :map, default: %{}
      timestamps(type: :utc_datetime_usec)
    end
  end

  defmodule PreferenceWithoutTimestamps do
    @moduledoc false
    use Ecto.Schema

    schema "backpex_preferences" do
      field :account_id, :integer
      field :workspace_id, :integer
      field :key, :string
      field :value, :map, default: %{}
    end
  end

  @opts [repo: FakeRepo, schema: Preference, scope_fields: [:user_id, :tenant_id]]
  @scope %{user_id: 7, tenant_id: 70}
  @other_tenant_scope %{user_id: 7, tenant_id: 71}
  @other_user_scope %{user_id: 8, tenant_id: 70}

  setup do
    {:ok, ctx: %Context{scope: @scope}, unscoped: %Context{scope: :unscoped}}
  end

  describe "client_namespace/2" do
    test "contains exactly the configured scope fields", %{ctx: ctx} do
      assert {:ok, {FakeRepo, Preference, "", %{user_id: 7, tenant_id: 70}}} =
               EctoAdapter.client_namespace(ctx, @opts)
    end

    test "distinguishes storage key prefixes", %{ctx: ctx} do
      prefixed_opts = Keyword.put(@opts, :storage_key_prefix, "backpex.")

      refute EctoAdapter.client_namespace(ctx, @opts) ==
               EctoAdapter.client_namespace(ctx, prefixed_opts)

      assert {:ok, {FakeRepo, Preference, "backpex.", %{user_id: 7, tenant_id: 70}}} =
               EctoAdapter.client_namespace(ctx, prefixed_opts)
    end

    test "ignores scope values the adapter does not use" do
      opts = Keyword.put(@opts, :scope_fields, [:user_id])
      first = %Context{scope: %{user_id: 7, tenant_id: 70}}
      second = %Context{scope: %{user_id: 7, tenant_id: 71}}

      assert EctoAdapter.client_namespace(first, opts) == EctoAdapter.client_namespace(second, opts)
    end

    test "rejects an unresolved or incomplete scope", %{unscoped: unscoped} do
      assert EctoAdapter.client_namespace(unscoped, @opts) == {:error, :unscoped}

      assert EctoAdapter.client_namespace(%Context{scope: %{user_id: 7}}, @opts) ==
               {:error, {:invalid_scope, [:tenant_id]}}
    end
  end

  describe "get/3" do
    test "returns :not_found when nothing is stored", %{ctx: ctx} do
      assert {:ok, :not_found} = EctoAdapter.get(ctx, "resource:PostLive:order", @opts)
    end

    test "round-trips a map value", %{ctx: ctx} do
      {:ok, :persisted} = EctoAdapter.put(ctx, "resource:PostLive:order", %{"by" => "id"}, @opts)

      assert {:ok, %{"by" => "id"}} = EctoAdapter.get(ctx, "resource:PostLive:order", @opts)
    end

    test "round-trips scalars the :map column cannot hold bare", %{ctx: ctx} do
      for value <- [true, false, "dark", 42] do
        {:ok, :persisted} = EctoAdapter.put(ctx, "global.scalar", value, @opts)
        assert {:ok, ^value} = EctoAdapter.get(ctx, "global.scalar", @opts)
      end
    end

    test "does not read the same user's row from another tenant", %{ctx: ctx} do
      {:ok, :persisted} =
        EctoAdapter.put(%Context{scope: @other_tenant_scope}, "global.theme", "dark", @opts)

      assert {:ok, :not_found} = EctoAdapter.get(ctx, "global.theme", @opts)
    end

    test "does not read another user's row in the same tenant", %{ctx: ctx} do
      {:ok, :persisted} = EctoAdapter.put(%Context{scope: @other_user_scope}, "global.theme", "dark", @opts)

      assert {:ok, :not_found} = EctoAdapter.get(ctx, "global.theme", @opts)
    end

    test "reports :not_found without a scope", %{unscoped: ctx} do
      assert {:ok, :not_found} = EctoAdapter.get(ctx, "global.theme", @opts)
    end

    test "reports missing configured scope fields" do
      ctx = %Context{scope: %{user_id: 7}}

      assert {:error, {:invalid_scope, [:tenant_id]}} = EctoAdapter.get(ctx, "global.theme", @opts)
    end
  end

  describe "get_map/3" do
    setup %{ctx: ctx} do
      {:ok, :persisted} = EctoAdapter.put(ctx, "global.sidebar_section.blog", true, @opts)
      {:ok, :persisted} = EctoAdapter.put(ctx, "global.sidebar_section.users", false, @opts)
      {:ok, :persisted} = EctoAdapter.put(ctx, "global.sidebar_open", true, @opts)
      :ok
    end

    test "returns the subtree relative to the prefix", %{ctx: ctx} do
      assert {:ok, %{"blog" => true, "users" => false}} =
               EctoAdapter.get_map(ctx, "global.sidebar_section", @opts)
    end

    test "nests deeper subtrees", %{ctx: ctx} do
      assert {:ok, subtree} = EctoAdapter.get_map(ctx, "global", @opts)

      assert subtree == %{
               "sidebar_open" => true,
               "sidebar_section" => %{"blog" => true, "users" => false}
             }
    end

    test "nests colon-form resource keys", %{ctx: ctx} do
      {:ok, :persisted} = EctoAdapter.put(ctx, "resource:MyApp.PostLive:order", %{"by" => "id"}, @opts)

      assert {:ok, %{"MyApp.PostLive" => %{"order" => %{"by" => "id"}}}} =
               EctoAdapter.get_map(ctx, "resource", @opts)
    end

    test "drops rows the LIKE wildcard over-matched", %{ctx: ctx} do
      {:ok, :persisted} = EctoAdapter.put(ctx, "global.sidebarXsection.blog", true, @opts)

      assert {:ok, %{"blog" => true, "users" => false}} =
               EctoAdapter.get_map(ctx, "global.sidebar_section", @opts)
    end

    test "returns an empty map when nothing matches", %{ctx: ctx} do
      assert {:ok, %{}} = EctoAdapter.get_map(ctx, "resource", @opts)
    end

    test "does not read rows from another scope" do
      assert {:ok, %{}} = EctoAdapter.get_map(%Context{scope: @other_tenant_scope}, "global", @opts)
    end

    test "returns an empty map without a scope", %{unscoped: ctx} do
      assert {:ok, %{}} = EctoAdapter.get_map(ctx, "global", @opts)
    end

    test "strips the storage key prefix before nesting", %{ctx: ctx} do
      opts = Keyword.put(@opts, :storage_key_prefix, "backpex.")

      {:ok, :persisted} = EctoAdapter.put(ctx, "global.sidebar_section.blog", true, opts)
      {:ok, :persisted} = EctoAdapter.put(ctx, "global.sidebar_section.users", false, opts)

      assert {:ok, %{"blog" => true, "users" => false}} =
               EctoAdapter.get_map(ctx, "global.sidebar_section", opts)
    end
  end

  describe "put/4" do
    test "wraps values in the storage envelope", %{ctx: ctx} do
      {:ok, :persisted} = EctoAdapter.put(ctx, "global.theme", "dark", @opts)

      assert [{"global.theme", %{"value" => "dark"}}] = FakeRepo.rows_for([7, 70])
    end

    test "stores prefixed keys and reads them through their logical key", %{ctx: ctx} do
      opts = Keyword.put(@opts, :storage_key_prefix, "backpex.")

      {:ok, :persisted} = EctoAdapter.put(ctx, "global.theme", "dark", opts)

      assert [{"backpex.global.theme", %{"value" => "dark"}}] = FakeRepo.rows_for([7, 70])
      assert {:ok, "dark"} = EctoAdapter.get(ctx, "global.theme", opts)
      assert {:ok, :not_found} = EctoAdapter.get(ctx, "backpex.global.theme", opts)
    end

    test "upserts inside the complete scope rather than duplicating a key", %{ctx: ctx} do
      {:ok, :persisted} = EctoAdapter.put(ctx, "global.theme", "dark", @opts)
      {:ok, :persisted} = EctoAdapter.put(ctx, "global.theme", "light", @opts)

      assert [{"global.theme", %{"value" => "light"}}] = FakeRepo.rows_for([7, 70])
    end

    test "keeps the same key in two tenants", %{ctx: ctx} do
      {:ok, :persisted} = EctoAdapter.put(ctx, "global.theme", "dark", @opts)

      {:ok, :persisted} =
        EctoAdapter.put(%Context{scope: @other_tenant_scope}, "global.theme", "light", @opts)

      assert [{"global.theme", %{"value" => "dark"}}] = FakeRepo.rows_for([7, 70])
      assert [{"global.theme", %{"value" => "light"}}] = FakeRepo.rows_for([7, 71])
    end

    test "fails without a scope rather than writing an unreadable row", %{unscoped: ctx} do
      assert {:error, :unscoped} = EctoAdapter.put(ctx, "global.theme", "dark", @opts)
      assert [] = FakeRepo.rows_for([])
    end

    test "reports missing configured scope fields" do
      ctx = %Context{scope: %{user_id: 7}}

      assert {:error, {:invalid_scope, [:tenant_id]}} = EctoAdapter.put(ctx, "global.theme", "dark", @opts)
    end

    test "raises when a scope field is absent from the schema", %{ctx: ctx} do
      opts = Keyword.put(@opts, :scope_fields, [:user_id, :tenant_id, :workspace_id])

      assert_raise ArgumentError, ~r/unknown preference schema fields: \[:workspace_id\]/, fn ->
        EctoAdapter.put(ctx, "global.theme", "dark", opts)
      end
    end

    test "raises on invalid scope_fields", %{ctx: ctx} do
      for fields <- [[], [:user_id, :user_id], ["user_id"]] do
        opts = Keyword.put(@opts, :scope_fields, fields)

        assert_raise ArgumentError, ~r/:scope_fields must be a non-empty list of unique atoms/, fn ->
          EctoAdapter.put(ctx, "global.theme", "dark", opts)
        end
      end
    end

    test "raises when scope_fields contains adapter-owned fields", %{ctx: ctx} do
      for fields <- [[:user_id, :key], [:value, :tenant_id], [:key, :value]] do
        opts = Keyword.put(@opts, :scope_fields, fields)

        assert_raise ArgumentError, ~r/:scope_fields contains adapter-owned fields/, fn ->
          EctoAdapter.put(ctx, "global.theme", "dark", opts)
        end
      end
    end

    test "raises when storage_key_prefix is not a string", %{ctx: ctx} do
      opts = Keyword.put(@opts, :storage_key_prefix, :backpex)

      assert_raise ArgumentError, ~r/:storage_key_prefix must be a string/, fn ->
        EctoAdapter.put(ctx, "global.theme", "dark", opts)
      end
    end

    test "honors custom scope fields", %{ctx: _ctx} do
      opts = [
        repo: FakeRepo,
        schema: PreferenceWithoutTimestamps,
        scope_fields: [:account_id, :workspace_id]
      ]

      ctx = %Context{scope: %{account_id: 7, workspace_id: 9, ignored: true}}
      {:ok, :persisted} = EctoAdapter.put(ctx, "global.theme", "dark", opts)

      assert {:ok, "dark"} = EctoAdapter.get(ctx, "global.theme", opts)
    end
  end

  describe "put/4 write limits" do
    test "refuses a storage key over :max_key_bytes instead of surfacing a database error", %{ctx: ctx} do
      key = "custom." <> String.duplicate("a", 249)

      ExUnit.CaptureLog.capture_log(fn ->
        assert {:error, :key_too_long} = EctoAdapter.put(ctx, key, "x", @opts)
      end)

      assert [] = FakeRepo.rows_for([7, 70])
    end

    test "counts the storage prefix against :max_key_bytes", %{ctx: ctx} do
      key = "custom." <> String.duplicate("a", 248)
      assert {:ok, :persisted} = EctoAdapter.put(ctx, key, "x", @opts)

      prefixed_opts = Keyword.put(@opts, :storage_key_prefix, "backpex.")

      ExUnit.CaptureLog.capture_log(fn ->
        assert {:error, :key_too_long} = EctoAdapter.put(ctx, key, "x", prefixed_opts)
      end)
    end

    test "allows any key length with max_key_bytes: :infinity", %{ctx: ctx} do
      opts = Keyword.put(@opts, :max_key_bytes, :infinity)
      key = "custom." <> String.duplicate("a", 500)

      assert {:ok, :persisted} = EctoAdapter.put(ctx, key, "x", opts)
    end

    test "refuses a value over :max_value_bytes", %{ctx: ctx} do
      opts = Keyword.put(@opts, :max_value_bytes, 64)

      ExUnit.CaptureLog.capture_log(fn ->
        assert {:error, :too_large} = EctoAdapter.put(ctx, "custom.blob", String.duplicate("x", 100), opts)
      end)

      assert [] = FakeRepo.rows_for([7, 70])
      assert {:ok, :persisted} = EctoAdapter.put(ctx, "custom.blob", "small", opts)
    end

    test "allows any value size with max_value_bytes: :infinity", %{ctx: ctx} do
      opts = Keyword.put(@opts, :max_value_bytes, :infinity)

      assert {:ok, :persisted} =
               EctoAdapter.put(ctx, "custom.blob", String.duplicate("x", 100_000), opts)
    end

    test "refuses a new key once the scope holds :max_keys rows", %{ctx: ctx} do
      opts = Keyword.put(@opts, :max_keys, 2)

      assert {:ok, :persisted} = EctoAdapter.put(ctx, "custom.one", 1, opts)
      assert {:ok, :persisted} = EctoAdapter.put(ctx, "custom.two", 2, opts)

      ExUnit.CaptureLog.capture_log(fn ->
        assert {:error, :too_many_keys} = EctoAdapter.put(ctx, "custom.three", 3, opts)
      end)

      assert length(FakeRepo.rows_for([7, 70])) == 2
    end

    test "still updates an existing key at the :max_keys cap", %{ctx: ctx} do
      opts = Keyword.put(@opts, :max_keys, 2)

      assert {:ok, :persisted} = EctoAdapter.put(ctx, "custom.one", 1, opts)
      assert {:ok, :persisted} = EctoAdapter.put(ctx, "custom.two", 2, opts)
      assert {:ok, :persisted} = EctoAdapter.put(ctx, "custom.one", 11, opts)

      assert {:ok, 11} = EctoAdapter.get(ctx, "custom.one", opts)
    end

    test "counts keys per scope, not per table", %{ctx: ctx} do
      opts = Keyword.put(@opts, :max_keys, 1)

      assert {:ok, :persisted} = EctoAdapter.put(ctx, "custom.one", 1, opts)

      assert {:ok, :persisted} =
               EctoAdapter.put(%Context{scope: @other_user_scope}, "custom.one", 1, opts)

      assert {:ok, :persisted} =
               EctoAdapter.put(%Context{scope: @other_tenant_scope}, "custom.one", 1, opts)
    end

    test "allows unlimited keys with max_keys: :infinity", %{ctx: ctx} do
      opts = Keyword.put(@opts, :max_keys, :infinity)

      for index <- 1..5 do
        assert {:ok, :persisted} = EctoAdapter.put(ctx, "custom.key_#{index}", index, opts)
      end
    end

    test "raises on invalid limit options", %{ctx: ctx} do
      for {option, value} <- [max_key_bytes: 0, max_value_bytes: -1, max_keys: "many"] do
        opts = Keyword.put(@opts, option, value)

        assert_raise ArgumentError, ~r/must be a positive integer or :infinity/, fn ->
          EctoAdapter.put(ctx, "global.theme", "dark", opts)
        end
      end
    end
  end
end
