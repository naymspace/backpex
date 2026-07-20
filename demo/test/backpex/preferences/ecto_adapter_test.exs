defmodule Demo.Backpex.Preferences.EctoAdapterTest do
  @moduledoc """
  Integration coverage for `Backpex.Preferences.Adapters.Ecto` against real
  Postgres.

  Backpex's own suite has no repo, so it exercises the adapter with a query
  double. That leaves the parts only a database can answer: that the upsert's
  conflict target matches the unique index, that the `jsonb` envelope survives
  a round trip with its value types intact, and that the `LIKE` subtree query
  actually returns the rows it should. Those are what this file covers.
  """
  use Demo.DataCase, async: true

  alias Backpex.Preferences.Adapters.Ecto, as: EctoAdapter
  alias Backpex.Preferences.Context
  alias Demo.Preferences.UserPreference

  @opts [repo: Demo.Repo, schema: UserPreference]
  @identity 1
  @other_identity 2

  setup do
    {:ok, ctx: %Context{identity: @identity}}
  end

  describe "round trip through Postgres" do
    test "preserves value types across the jsonb envelope", %{ctx: ctx} do
      values = [
        {"global.bool_true", true},
        {"global.bool_false", false},
        {"global.string", "dark"},
        {"global.integer", 42},
        {"global.list", ["a", "b"]},
        {"global.map", %{"by" => "id", "direction" => "asc"}}
      ]

      for {key, value} <- values do
        assert {:ok, :persisted} = EctoAdapter.put(ctx, key, value, @opts)
      end

      for {key, value} <- values do
        assert {:ok, ^value} = EctoAdapter.get(ctx, key, @opts),
               "#{key} did not survive the round trip"
      end
    end

    test "stores nil distinguishably from a missing row", %{ctx: ctx} do
      assert {:ok, :persisted} = EctoAdapter.put(ctx, "global.explicit_nil", nil, @opts)

      assert {:ok, nil} = EctoAdapter.get(ctx, "global.explicit_nil", @opts)
      assert {:ok, :not_found} = EctoAdapter.get(ctx, "global.never_written", @opts)
    end
  end

  describe "upsert" do
    test "replaces the value without violating the unique index", %{ctx: ctx} do
      key = "resource:Demo.PostLive:order"

      assert {:ok, :persisted} = EctoAdapter.put(ctx, key, %{"by" => "id"}, @opts)
      assert {:ok, :persisted} = EctoAdapter.put(ctx, key, %{"by" => "title"}, @opts)

      assert [row] = Repo.all(UserPreference)
      assert row.value == %{"value" => %{"by" => "title"}}
    end

    test "preserves inserted_at on conflict", %{ctx: ctx} do
      key = "resource:Demo.PostLive:order"

      {:ok, :persisted} = EctoAdapter.put(ctx, key, %{"by" => "id"}, @opts)
      first = Repo.one!(UserPreference)

      {:ok, :persisted} = EctoAdapter.put(ctx, key, %{"by" => "title"}, @opts)
      second = Repo.one!(UserPreference)

      assert second.id == first.id
      assert second.inserted_at == first.inserted_at
    end

    test "keeps rows for different identities side by side", %{ctx: ctx} do
      key = "global.theme"

      {:ok, :persisted} = EctoAdapter.put(ctx, key, "dark", @opts)
      {:ok, :persisted} = EctoAdapter.put(%Context{identity: @other_identity}, key, "light", @opts)

      assert {:ok, "dark"} = EctoAdapter.get(ctx, key, @opts)
      assert {:ok, "light"} = EctoAdapter.get(%Context{identity: @other_identity}, key, @opts)
    end
  end

  describe "get_map/3" do
    setup %{ctx: ctx} do
      {:ok, :persisted} = EctoAdapter.put(ctx, "global.sidebar_section.blog", true, @opts)
      {:ok, :persisted} = EctoAdapter.put(ctx, "global.sidebar_section.users", false, @opts)
      {:ok, :persisted} = EctoAdapter.put(ctx, "global.sidebar_open", true, @opts)
      {:ok, :persisted} = EctoAdapter.put(%Context{identity: @other_identity}, "global.sidebar_open", false, @opts)
      :ok
    end

    test "returns the subtree below the prefix", %{ctx: ctx} do
      assert {:ok, %{"blog" => true, "users" => false}} =
               EctoAdapter.get_map(ctx, "global.sidebar_section", @opts)
    end

    test "nests intermediate levels", %{ctx: ctx} do
      assert {:ok, subtree} = EctoAdapter.get_map(ctx, "global", @opts)

      assert subtree == %{
               "sidebar_open" => true,
               "sidebar_section" => %{"blog" => true, "users" => false}
             }
    end

    test "does not leak another identity's rows" do
      assert {:ok, subtree} = EctoAdapter.get_map(%Context{identity: @other_identity}, "global", @opts)

      assert subtree == %{"sidebar_open" => false}
    end

    # Postgres LIKE treats `_` as a single-character wildcard, so the query
    # genuinely returns this row and the adapter has to discard it.
    test "discards rows the LIKE wildcard over-matched", %{ctx: ctx} do
      {:ok, :persisted} = EctoAdapter.put(ctx, "global.sidebarXsection.blog", true, @opts)

      assert {:ok, subtree} = EctoAdapter.get_map(ctx, "global.sidebar_section", @opts)
      assert subtree == %{"blog" => true, "users" => false}
    end

    test "returns an empty map when the prefix has no rows", %{ctx: ctx} do
      assert {:ok, %{}} = EctoAdapter.get_map(ctx, "resource", @opts)
    end
  end
end
