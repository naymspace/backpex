defmodule Backpex.Preferences.Adapters.EctoTest do
  use ExUnit.Case, async: true

  alias Backpex.Preferences.Adapters.Ecto, as: EctoAdapter
  alias Backpex.Preferences.Context
  alias Backpex.Test.Preferences.FakeRepo

  defmodule Preference do
    @moduledoc false
    use Ecto.Schema

    schema "backpex_user_preferences" do
      field :user_id, :integer
      field :key, :string
      field :value, :map, default: %{}
      timestamps(type: :utc_datetime_usec)
    end
  end

  defmodule PreferenceWithoutTimestamps do
    @moduledoc false
    use Ecto.Schema

    schema "backpex_user_preferences" do
      field :account_id, :integer
      field :key, :string
      field :value, :map, default: %{}
    end
  end

  @opts [repo: FakeRepo, schema: Preference]
  @identity 7
  @other_identity 8

  setup do
    {:ok, ctx: %Context{identity: @identity}, unidentified: %Context{identity: :unidentified}}
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

    test "does not read another identity's row", %{ctx: ctx} do
      {:ok, :persisted} = EctoAdapter.put(%Context{identity: @other_identity}, "global.theme", "dark", @opts)

      assert {:ok, :not_found} = EctoAdapter.get(ctx, "global.theme", @opts)
    end

    test "reports :not_found without an identity", %{unidentified: ctx} do
      assert {:ok, :not_found} = EctoAdapter.get(ctx, "global.theme", @opts)
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

    # `LIKE 'global.sidebar_section%'` also matches `global.sidebarXsection.*`,
    # so the adapter must reject on segments rather than trust the query.
    test "drops rows the LIKE wildcard over-matched", %{ctx: ctx} do
      {:ok, :persisted} = EctoAdapter.put(ctx, "global.sidebarXsection.blog", true, @opts)

      assert {:ok, subtree} = EctoAdapter.get_map(ctx, "global.sidebar_section", @opts)
      assert subtree == %{"blog" => true, "users" => false}
    end

    test "returns an empty map when nothing matches", %{ctx: ctx} do
      assert {:ok, %{}} = EctoAdapter.get_map(ctx, "resource", @opts)
    end

    test "does not read another identity's rows" do
      assert {:ok, %{}} = EctoAdapter.get_map(%Context{identity: @other_identity}, "global", @opts)
    end

    test "returns an empty map without an identity", %{unidentified: ctx} do
      assert {:ok, %{}} = EctoAdapter.get_map(ctx, "global", @opts)
    end
  end

  describe "put/4" do
    test "wraps values in the storage envelope", %{ctx: ctx} do
      {:ok, :persisted} = EctoAdapter.put(ctx, "global.theme", "dark", @opts)

      assert [{"global.theme", %{"value" => "dark"}}] = FakeRepo.rows_for(@identity)
    end

    test "upserts rather than duplicating a key", %{ctx: ctx} do
      {:ok, :persisted} = EctoAdapter.put(ctx, "global.theme", "dark", @opts)
      {:ok, :persisted} = EctoAdapter.put(ctx, "global.theme", "light", @opts)

      assert [{"global.theme", %{"value" => "light"}}] = FakeRepo.rows_for(@identity)
    end

    test "fails without an identity rather than writing an unreadable row", %{unidentified: ctx} do
      assert {:error, :unidentified} = EctoAdapter.put(ctx, "global.theme", "dark", @opts)
      assert [] = FakeRepo.rows_for(:unidentified)
    end

    test "honors a custom :identity_field", %{ctx: ctx} do
      opts = [repo: FakeRepo, schema: PreferenceWithoutTimestamps, identity_field: :account_id]

      {:ok, :persisted} = EctoAdapter.put(ctx, "global.theme", "dark", opts)

      assert {:ok, "dark"} = EctoAdapter.get(ctx, "global.theme", opts)
    end
  end
end
