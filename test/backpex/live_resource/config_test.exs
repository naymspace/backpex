defmodule Backpex.LiveResource.ConfigTest do
  use ExUnit.Case, async: true

  import Ecto.Query, only: [dynamic: 2]

  alias Backpex.Filter
  alias Backpex.ItemAction
  alias Backpex.LiveResource.Config
  alias Backpex.LiveResource.Form
  alias Backpex.LiveResource.Index
  alias Backpex.LiveResource.Show
  alias Backpex.Metric
  alias Backpex.Metrics.Value
  alias Backpex.ResourceAction
  alias Phoenix.LiveView.Socket

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

  defmodule QuerySchemaMetric do
    @moduledoc false
    def query(_query, _select, _repo), do: 1
    def config_schema, do: [select: [type: :any, doc: "The column to count."]]
  end

  defmodule TranslatedSchemaMetric do
    @moduledoc false
    def data(_metric, _assigns), do: 1
    def config_schema, do: [label: [type: :string, doc: "Label #{System.unique_integer()}"]]
  end

  # A LiveResource whose configuration is valid. Each view test overrides one callback with an invalid configuration.
  defmodule ViewLive do
    @moduledoc false
    defmacro __using__(_opts) do
      quote do
        def config(:fluid?), do: false
        def config(:per_page_options), do: [15]
        def config(:per_page_default), do: 15
        def config(:init_order), do: %{by: :id, direction: :asc}
        def fields(_action, _assigns), do: []
        def singular_name, do: "Post"
        def can?(_assigns, _action, _item), do: true
        def panels, do: []
        def item_actions(default_actions), do: default_actions
        def resource_actions, do: []
        def filters(_assigns), do: []

        defoverridable panels: 0, item_actions: 1, resource_actions: 0, filters: 1
      end
    end
  end

  defmodule InvalidPanelsLive do
    @moduledoc false
    use ViewLive

    def panels, do: [names: %{label: "Names"}]
  end

  defmodule InvalidItemActionsLive do
    @moduledoc false
    use ViewLive

    def item_actions(default_actions), do: Keyword.put(default_actions, :archive, %{module: SomeAction, olny: [:row]})
  end

  defmodule InvalidResourceActionsLive do
    @moduledoc false
    use ViewLive

    def resource_actions, do: [invite: %{module: SomeAction, label: "Invite"}]
  end

  defmodule InvalidFiltersLive do
    @moduledoc false
    use ViewLive

    def filters(_assigns), do: [published: %{module: SomeFilter, lable: "Published?"}]
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

    test "rejects a map with keys that are not atoms" do
      assert_raise ArgumentError,
                   error("filter", "published", ~s(expected a map with atom keys, got: %{"module")),
                   fn ->
                     Filter.validate_configs!([published: %{"module" => SomeFilter}], PostLive)
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
        classes: %{module: Value, label: "Total", class: ["w-full", "lg:w-1/3"], select: :likes, format: nil},
        no_class: %{module: Value, label: "Total", class: nil, select: :likes}
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

    test "keeps the select required when the config_schema/0 of a metric module describes it again" do
      assert_raise ArgumentError, error("metric", "custom", "required :select option not found"), fn ->
        Metric.validate_configs!([custom: %{module: QuerySchemaMetric}], PostLive)
      end
    end

    test "compiles the config_schema/0 of a metric module only once" do
      metrics = [balance: %{module: TranslatedSchemaMetric, label: "Balance"}]

      Metric.validate_configs!(metrics, PostLive)
      compiled_schema = :persistent_term.get({Metric, TranslatedSchemaMetric})

      Metric.validate_configs!(metrics, PostLive)
      assert :persistent_term.get({Metric, TranslatedSchemaMetric}) == compiled_schema
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
      panels = [names: "Names", contact: "Contact", extra: nil]

      assert Config.validate_panels!(panels, PostLive) == panels
      assert Config.validate_panels!([], PostLive) == []
    end

    test "rejects a label that is not a string" do
      assert_raise ArgumentError,
                   error("panel", "names", "expected :names option to match at least one given type"),
                   fn ->
                     Config.validate_panels!([names: %{label: "Names"}], PostLive)
                   end
    end

    test "rejects a return value that is not a keyword list" do
      message = shape_error("panels/0", "a keyword list of labels")

      assert_raise ArgumentError, message, fn -> Config.validate_panels!(["Names"], PostLive) end
    end
  end

  describe "validation in the views" do
    test "the index, show and form views validate the panels when they mount" do
      for {view, live_action} <- [{Index, :index}, {Show, :show}, {Form, :edit}] do
        assert_raise ArgumentError, view_error("panel", "names", InvalidPanelsLive), fn ->
          view.mount(%{}, %{}, socket(live_action), InvalidPanelsLive)
        end
      end
    end

    test "the index view validates the item actions" do
      assert_raise ArgumentError, view_error("item action", "archive", InvalidItemActionsLive), fn ->
        Index.handle_params(%{}, "", socket(:index, InvalidItemActionsLive))
      end
    end

    test "the show view validates the item actions when it mounts" do
      assert_raise ArgumentError, view_error("item action", "archive", InvalidItemActionsLive), fn ->
        Show.mount(%{}, %{}, socket(:show), InvalidItemActionsLive)
      end
    end

    test "the index view validates the resource actions" do
      socket = socket(:resource_action, InvalidResourceActionsLive)

      assert_raise ArgumentError, view_error("resource action", "invite", InvalidResourceActionsLive), fn ->
        Index.handle_params(%{"backpex_id" => "invite"}, "", socket)
      end
    end

    test "the index view validates the filters" do
      assert_raise ArgumentError, view_error("filter", "published", InvalidFiltersLive), fn ->
        Index.handle_params(%{}, "", socket(:index, InvalidFiltersLive))
      end
    end
  end

  defp view_error(kind, key, live_resource) do
    ~r/\AConfiguration error for #{kind} "#{key}" in "#{Regex.escape(to_string(live_resource))}"/
  end

  defp socket(live_action, live_resource \\ nil) do
    %Socket{assigns: %{__changed__: %{}, live_action: live_action, live_resource: live_resource, fields: []}}
  end
end
