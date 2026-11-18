defmodule Backpex.LiveResource.ConfigTest do
  use ExUnit.Case, async: true

  import Ecto.Query, only: [dynamic: 2]

  alias Backpex.Filter
  alias Backpex.ItemAction
  alias Backpex.LiveResource.Config
  alias Backpex.Metric
  alias Backpex.Metrics.Value
  alias Backpex.ResourceAction

  defmodule PostLive do
    @moduledoc false
  end

  defmodule DataMetric do
    @moduledoc false
    def data(_metric, _assigns), do: 1
  end

  defmodule QueryMetric do
    @moduledoc false
    def query(_query, _select, _repo), do: 1
  end

  defmodule SchemaMetric do
    @moduledoc false
    def data(_metric, _assigns), do: 1
    def config_schema, do: [color: [type: {:in, [:primary, :secondary]}, required: true]]
  end

  defp error(kind, key, message) do
    live_resource = Regex.escape("Elixir.Backpex.LiveResource.ConfigTest.PostLive")

    ~r/\AConfiguration error for #{kind} "#{key}" in "#{live_resource}".\n\n#{Regex.escape(message)}/
  end

  defp shape_error(callback, expected) do
    ~r/\AConfiguration error for #{Regex.escape(callback)} in ".*PostLive".\n\nexpected #{expected}, got: /
  end

  describe "Backpex.Filter.validate_configs!/2" do
    test "returns valid filters unchanged" do
      filters = [
        category_id: %{module: SomeFilter},
        user_id: %{module: SomeFilter, label: "Users"},
        published: %{module: SomeFilter, label: "Published?", default: ["published"]},
        likes: %{
          module: SomeFilter,
          label: "Likes",
          presets: [%{label: "Over 100", values: fn -> %{"start" => 100, "end" => nil} end}]
        }
      ]

      assert Filter.validate_configs!(filters, PostLive) == filters
      assert Filter.validate_configs!([], PostLive) == []
    end

    test "rejects an unknown key" do
      assert_raise ArgumentError, error("filter", "published", "unknown options [:lable], valid options are:"), fn ->
        Filter.validate_configs!([published: %{module: SomeFilter, lable: "Published?"}], PostLive)
      end

      assert_raise ArgumentError, error("filter", "published", "unknown options [:preset]"), fn ->
        Filter.validate_configs!([published: %{module: SomeFilter, preset: []}], PostLive)
      end
    end

    test "requires the module" do
      assert_raise ArgumentError, error("filter", "published", "required :module option not found"), fn ->
        Filter.validate_configs!([published: %{label: "Published?"}], PostLive)
      end
    end

    test "rejects an unknown key in a preset" do
      message = "invalid list element at position 0 in :presets option: unknown options [:value]"

      assert_raise ArgumentError, error("filter", "likes", message), fn ->
        Filter.validate_configs!([likes: %{module: SomeFilter, presets: [%{label: "All", value: 1}]}], PostLive)
      end
    end

    test "rejects a return value that is not a keyword list of maps" do
      message = shape_error("filters/1", "a keyword list of maps")

      assert_raise ArgumentError, message, fn -> Filter.validate_configs!(%{published: %{}}, PostLive) end
      assert_raise ArgumentError, message, fn -> Filter.validate_configs!([published: SomeFilter], PostLive) end

      assert_raise ArgumentError, message, fn ->
        Filter.validate_configs!([published: [module: SomeFilter]], PostLive)
      end
    end
  end

  describe "Backpex.Metric.validate_configs!/2" do
    test "returns valid value metrics unchanged" do
      metrics = [
        total: %{module: Value, label: "Total", select: dynamic([p], sum(p.likes))},
        formatted: %{
          module: Value,
          label: "Total",
          class: "lg:w-1/4",
          select: dynamic([p], sum(p.likes)),
          format: &Integer.to_string/1
        },
        classes: %{module: Value, label: "Total", class: ["w-full", "lg:w-1/3"], select: :likes, format: nil}
      ]

      assert Metric.validate_configs!(metrics, PostLive) == metrics
    end

    test "rejects an unknown key of a value metric" do
      assert_raise ArgumentError, error("metric", "total", "unknown options [:lable], valid options are:"), fn ->
        Metric.validate_configs!([total: %{module: Value, lable: "Total", label: "Total", select: :likes}], PostLive)
      end
    end

    test "requires the label and the select of a value metric" do
      assert_raise ArgumentError, error("metric", "total", "required :label option not found"), fn ->
        Metric.validate_configs!([total: %{module: Value, select: :likes}], PostLive)
      end

      assert_raise ArgumentError, error("metric", "total", "required :select option not found"), fn ->
        Metric.validate_configs!([total: %{module: Value, label: "Total"}], PostLive)
      end
    end

    test "requires the module" do
      assert_raise ArgumentError, error("metric", "total", "required :module option not found"), fn ->
        Metric.validate_configs!([total: %{label: "Total", select: :likes}], PostLive)
      end
    end

    test "passes on the keys of a metric module without config_schema/0" do
      metrics = [
        balance: %{module: DataMetric, label: "Balance", color: :primary},
        custom: %{module: QueryMetric, select: :likes, color: :primary}
      ]

      assert Metric.validate_configs!(metrics, PostLive) == metrics
    end

    test "requires the select unless the metric module implements data/2" do
      assert_raise ArgumentError, error("metric", "custom", "required :select option not found"), fn ->
        Metric.validate_configs!([custom: %{module: QueryMetric, label: "Custom"}], PostLive)
      end
    end

    test "validates against the config_schema/0 of the metric module" do
      metrics = [balance: %{module: SchemaMetric, color: :primary}]

      assert Metric.validate_configs!(metrics, PostLive) == metrics

      assert_raise ArgumentError, error("metric", "balance", "unknown options [:colour]"), fn ->
        Metric.validate_configs!([balance: %{module: SchemaMetric, color: :primary, colour: :primary}], PostLive)
      end

      assert_raise ArgumentError, error("metric", "balance", "invalid value for :color option"), fn ->
        Metric.validate_configs!([balance: %{module: SchemaMetric, color: :red}], PostLive)
      end
    end
  end

  describe "Backpex.ItemAction.validate_configs!/2" do
    test "returns valid item actions unchanged" do
      item_actions =
        ItemAction.default_actions() ++
          [
            soft_delete: %{module: SomeAction},
            duplicate: %{module: SomeAction, only: [:row, :show]},
            archive: %{module: SomeAction, except: [:index]}
          ]

      assert ItemAction.validate_configs!(item_actions, PostLive) == item_actions
    end

    test "rejects an unknown key" do
      assert_raise ArgumentError, error("item action", "archive", "unknown options [:olny], valid options are:"), fn ->
        ItemAction.validate_configs!([archive: %{module: SomeAction, olny: [:row]}], PostLive)
      end
    end

    test "rejects an unknown placement" do
      assert_raise ArgumentError, error("item action", "archive", "invalid list in :only option"), fn ->
        ItemAction.validate_configs!([archive: %{module: SomeAction, only: [:rows]}], PostLive)
      end
    end

    test "requires the module" do
      assert_raise ArgumentError, error("item action", "archive", "required :module option not found"), fn ->
        ItemAction.validate_configs!([archive: %{only: [:row]}], PostLive)
      end
    end

    test "rejects a return value that is not a keyword list of maps" do
      assert_raise ArgumentError, shape_error("item_actions/1", "a keyword list of maps"), fn ->
        ItemAction.validate_configs!([SomeAction], PostLive)
      end
    end
  end

  describe "Backpex.ResourceAction.validate_configs!/2" do
    test "returns valid resource actions unchanged" do
      resource_actions = [invite: %{module: SomeAction}, upload: %{module: SomeAction}]

      assert ResourceAction.validate_configs!(resource_actions, PostLive) == resource_actions
      assert ResourceAction.validate_configs!([], PostLive) == []
    end

    test "rejects an unknown key" do
      assert_raise ArgumentError, error("resource action", "invite", "unknown options [:label]"), fn ->
        ResourceAction.validate_configs!([invite: %{module: SomeAction, label: "Invite"}], PostLive)
      end
    end

    test "requires the module" do
      assert_raise ArgumentError, error("resource action", "invite", "required :module option not found"), fn ->
        ResourceAction.validate_configs!([invite: %{}], PostLive)
      end
    end
  end

  describe "validate_panels!/2" do
    test "returns valid panels unchanged" do
      panels = [names: "Names", contact: "Contact"]

      assert Config.validate_panels!(panels, PostLive) == panels
      assert Config.validate_panels!([], PostLive) == []
    end

    test "rejects a label that is not a string" do
      assert_raise ArgumentError, error("panel", "names", "invalid value for :names option: expected string"), fn ->
        Config.validate_panels!([names: %{label: "Names"}], PostLive)
      end
    end

    test "rejects a return value that is not a keyword list" do
      message = shape_error("panels/0", "a keyword list of labels")

      assert_raise ArgumentError, message, fn -> Config.validate_panels!(["Names"], PostLive) end
    end
  end
end
