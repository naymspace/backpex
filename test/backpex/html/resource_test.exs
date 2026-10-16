defmodule Backpex.HTML.ResourceTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias Backpex.Filters.Select
  alias Backpex.HTML.Resource
  alias Plug.Conn.Query

  defmodule ContextLive do
    @moduledoc false
    def translate({msg, _opts}), do: msg
    def config(:full_text_search), do: nil
  end

  defmodule MarkerFilter do
    @moduledoc false
    use Phoenix.Component

    def label, do: "Marker"

    def type(_assigns), do: :string

    def changeset(changeset, _field, _assigns), do: changeset

    def render_form(assigns) do
      ~H"""
      <span id="marker">{@marker}</span>
      """
    end
  end

  describe "resource_filters/1" do
    test "passes the given context to the callbacks of filters" do
      html =
        render_component(&Resource.resource_filters/1,
          live_resource: ContextLive,
          search_placeholder: "Search",
          filters: [marker: %{module: MarkerFilter}],
          marker: "assigns",
          backpex_context: %{marker: "context"}
        )

      assert html =~ ~s(<span id="marker">context</span>)
    end

    test "passes its own assigns to the callbacks of filters when called without a context" do
      html =
        render_component(&Resource.resource_filters/1,
          live_resource: ContextLive,
          search_placeholder: "Search",
          filters: [marker: %{module: MarkerFilter}],
          marker: "assigns",
          backpex_view_context: %{marker: "view context"}
        )

      assert html =~ ~s(<span id="marker">assigns</span>)
    end
  end

  defmodule BooleanFilter do
    @moduledoc false
    use Backpex.Filters.Boolean

    @impl Backpex.Filter
    def label, do: "Published"

    @impl Backpex.Filters.Boolean
    def options(_assigns) do
      [
        %{label: "Published", key: "published", predicate: dynamic([x], x.published)},
        %{label: "Not published", key: "not_published", predicate: dynamic([x], not x.published)}
      ]
    end
  end

  defmodule MultiSelectFilter do
    @moduledoc false
    use Backpex.Filters.MultiSelect

    @impl Backpex.Filter
    def label, do: "Users"

    @impl Select
    def prompt, do: "Select users ..."

    @impl Select
    def options(_assigns), do: [{"Jane", "a"}, {"John", "b"}]
  end

  defmodule RangeFilter do
    @moduledoc false
    use Backpex.Filters.Range

    @impl Backpex.Filter
    def label, do: "Likes"

    @impl Backpex.Filters.Range
    def type, do: :number
  end

  defmodule SelectFilter do
    @moduledoc false
    use Backpex.Filters.Select

    @impl Backpex.Filter
    def label, do: "Category"

    @impl Select
    def prompt, do: "Select category ..."

    @impl Select
    def options(_assigns), do: [{"Tech", "tech"}, {"News", "news"}]
  end

  describe "resource_filters/1 with filter values from the URL or persisted filters" do
    @filters [
      published: %{module: BooleanFilter},
      user_id: %{module: MultiSelectFilter},
      likes: %{module: RangeFilter},
      category: %{module: SelectFilter}
    ]

    @wrong_shapes [
      %{"published" => "published"},
      %{"user_id" => "a"},
      %{"likes" => "abc"},
      %{"likes" => ["abc"]},
      %{"likes" => %{"start" => %{"a" => "b"}, "end" => ""}},
      %{"likes" => %{"start" => "", "end" => ["a"]}},
      %{"category" => ["tech"]},
      %{"published" => "published", "user_id" => "a", "likes" => "abc", "category" => ["tech"]}
    ]

    defp render_filters(raw_filters, opts \\ []) do
      changeset = Backpex.FilterValidation.build_changeset(raw_filters, @filters, %{})

      form_assigns =
        if Keyword.get(opts, :filter_form, true),
          do: [filter_form: Phoenix.Component.to_form(changeset, as: :filters)],
          else: []

      # The library tests have no error translator configured, so the fallback translator warns about the
      # `:type` option of cast errors. The warnings are not captured: capturing `:standard_error` re-registers
      # the named device, so other async tests that write to stderr meanwhile would crash.
      render_component(
        &Resource.resource_filters/1,
        [
          live_resource: ContextLive,
          search_placeholder: "Search",
          filters: @filters,
          query_options: %{filters: raw_filters},
          filter_values: Backpex.FilterValidation.valid_values(changeset)
        ] ++ form_assigns
      )
    end

    test "renders the form without values of the wrong shape and shows the cast error" do
      for raw_filters <- @wrong_shapes do
        html = render_filters(raw_filters)

        assert html =~ ~s(id="filter-form")
        assert html =~ ~s(<p class="text-error)
        refute html =~ "checked"
        refute html =~ "<option selected"

        # The invalid value can be cleared.
        for {field, _value} <- raw_filters do
          assert html =~ ~s(phx-click="clear-filter" phx-value-field="#{field}")
        end
      end
    end

    test "renders the form without values of the wrong shape when called without a filter form" do
      for raw_filters <- @wrong_shapes do
        html = render_filters(raw_filters, filter_form: false)

        assert html =~ ~s(id="filter-form")
        assert html =~ ~s(<p class="text-error)
        refute html =~ "checked"
      end
    end

    test "keeps values of the right shape in the form" do
      for opts <- [[], [filter_form: false]] do
        html =
          render_filters(
            %{
              "published" => ["published"],
              "user_id" => ["a"],
              "likes" => %{"start" => "1", "end" => "5"},
              "category" => "news"
            },
            opts
          )

        refute html =~ ~s(<p class="text-error)
        assert html =~ ~r/value="published"\s+checked/
        assert html =~ "1 selected"
        assert html =~ ~s(value="5")
        assert html =~ ~s(<option selected value="news">)
      end
    end
  end

  describe "filter_presets/1" do
    test "renders each preset as a button that does not submit the filter form" do
      html =
        render_component(&Resource.filter_presets/1,
          filter_name: :inserted_at,
          presets: [%{label: "Last 7 Days"}, %{label: "Last 14 Days"}]
        )

      buttons = html |> LazyHTML.from_fragment() |> LazyHTML.query("button")

      assert Enum.map(buttons, &String.trim(LazyHTML.text(&1))) == ["Last 7 Days", "Last 14 Days"]
      assert LazyHTML.attribute(buttons, "type") == ["button", "button"]
      assert LazyHTML.attribute(buttons, "phx-click") == ["filter-preset-selected", "filter-preset-selected"]
      assert LazyHTML.attribute(buttons, "phx-value-field") == ["inserted_at", "inserted_at"]
      assert LazyHTML.attribute(buttons, "phx-value-preset-index") == ["0", "1"]
    end
  end

  defmodule ShowPanelLive do
    @moduledoc false
    def config(:primary_key), do: :id

    def can?(assigns, :edit, _item) do
      send(self(), {:can?, assigns})
      true
    end
  end

  defmodule MarkerField do
    @moduledoc false
    use Phoenix.LiveComponent

    def render(assigns) do
      ~H"""
      <span id="marker">{@marker} {@live_action}</span>
      """
    end
  end

  describe "show_panel/1" do
    test "passes its own assigns to fields and callbacks when called without a context" do
      html =
        render_component(&Resource.show_panel/1,
          panel_fields: [marker: %{label: "Marker"}],
          item: %{id: 1, marker: "value"},
          fields: [marker: %{module: MarkerField, label: "Marker"}],
          live_resource: ShowPanelLive,
          live_action: :show,
          marker: "assigns"
        )

      assert html =~ ~s(<span id="marker">assigns show</span>)
      assert_received {:can?, %{marker: "assigns", live_action: :show}}
    end
  end

  defmodule ReadonlyField do
    @moduledoc false
    use Phoenix.LiveComponent

    def render(assigns) do
      ~H"""
      <span id="readonly">{to_string(@readonly)}</span>
      """
    end
  end

  describe "resource_field/1" do
    setup do
      readonly = fn %{item: item} -> item.locked end

      %{fields: [title: %{module: ReadonlyField, label: "Title", readonly: readonly}]}
    end

    for {description, context} <- [
          {"without an item", %{live_action: :index, item: nil}},
          {"with a list of context assigns", %{live_action: :index}}
        ] do
      test "evaluates readonly with the row item when called with a context #{description}", %{fields: fields} do
        for locked <- [true, false] do
          html =
            render_component(&Resource.resource_field/1,
              name: :title,
              item: %{id: 1, title: "Title", locked: locked},
              fields: fields,
              live_resource: ShowPanelLive,
              backpex_context: unquote(Macro.escape(context))
            )

          assert html =~ ~s(<span id="readonly">#{locked}</span>)
        end
      end
    end

    test "passes the name and the row item of the field to can?/3 when called with a context", %{fields: fields} do
      item = %{id: 1, title: "Title", locked: false}

      render_component(&Resource.resource_field/1,
        name: :title,
        item: item,
        fields: fields,
        live_resource: ShowPanelLive,
        backpex_context: %{live_action: :index, item: nil, current_user: :user}
      )

      assert_received {:can?, %{name: :title, item: ^item, current_user: :user}}
    end

    test "passes the reserved assigns of the context to can?/3", %{fields: fields} do
      render_component(&Resource.resource_field/1,
        name: :title,
        item: %{id: 1, title: "Title", locked: false},
        fields: fields,
        live_resource: ShowPanelLive,
        backpex_context: %{live_action: :index, item: nil, socket: :socket, flash: %{"info" => "Saved"}}
      )

      assert_received {:can?, %{socket: :socket, flash: %{"info" => "Saved"}}}
    end

    test "evaluates readonly with the row item when called without a context", %{fields: fields} do
      html =
        render_component(&Resource.resource_field/1,
          name: :title,
          item: %{id: 1, title: "Title", locked: true},
          fields: fields,
          live_resource: ShowPanelLive
        )

      assert html =~ ~s(<span id="readonly">true</span>)
    end
  end

  defmodule AssignIconAction do
    @moduledoc false
    use Phoenix.Component

    def icon(assigns, item) do
      assigns = assign(assigns, :label, "icon-#{item.id}")

      ~H"""
      <span id="assign-icon">{@label}</span>
      """
    end

    def label(_assigns, _item), do: "Assign icon"
  end

  defmodule TableLive do
    @moduledoc false
    def config(:primary_key), do: :id
    def config(:context_assigns), do: [:current_user]
    def translate({msg, _opts}), do: msg
    def can?(_assigns, _action, _item), do: true
    def index_row_class(_assigns, _item, _selected, _index), do: nil
  end

  describe "resource_index_table/1" do
    for {description, context} <- [
          {"without a context", nil},
          {"with a context", %{__changed__: %{}, live_resource: TableLive, live_action: :index, current_user: :user}}
        ] do
      test "lets callbacks of item actions assign to their assigns #{description}" do
        context = unquote(Macro.escape(context))

        html =
          render_component(
            &Resource.resource_index_table/1,
            Map.merge(
              %{
                socket: nil,
                live_resource: TableLive,
                live_action: :index,
                params: %{},
                query_options: %{},
                fields: [],
                orderable_fields: [],
                items: [%{id: 1}],
                active_fields: [],
                selected_items: [],
                item_actions: [assign_icon: %{module: AssignIconAction, only: [:row]}]
              },
              if(context, do: %{backpex_context: context_with_actions(context)}, else: %{})
            )
          )

        assert html =~ ~s(<span id="assign-icon">icon-1</span>)
      end
    end
  end

  defp context_with_actions(assigns) do
    assigns
    |> Map.merge(%{params: %{}, item_actions: [assign_icon: %{module: AssignIconAction, only: [:row]}]})
    |> Backpex.LiveResource.context()
  end

  describe "pagination/1" do
    # Tests the component contract: every link is the unchanged return value of `page_path`. The regression test for
    # the index view's page links is in demo/test/demo_web/live/post/pagination_live_test.exs.
    for search <- ["R&D 100%", "C# dev", "1+1", "100%25", ":page"] do
      test "uses the path from page_path unchanged for the search #{inspect(search)}" do
        search = unquote(search)

        html =
          render_component(&Resource.pagination/1,
            current_page: 2,
            total_pages: 3,
            page_path: &("/admin/posts?" <> Query.encode(%{search: search, page: &1}))
          )

        links =
          html
          |> LazyHTML.from_fragment()
          |> LazyHTML.query("a")
          |> Enum.map(fn link ->
            [href] = LazyHTML.attribute(link, "href")
            %URI{path: "/admin/posts", query: query, fragment: nil} = URI.parse(href)
            Query.decode(query)
          end)

        assert links == [
                 %{"search" => search, "page" => "1"},
                 %{"search" => search, "page" => "1"},
                 %{"search" => search, "page" => "2"},
                 %{"search" => search, "page" => "3"},
                 %{"search" => search, "page" => "3"}
               ]
      end
    end
  end

  describe "lv_reserved_assigns/0" do
    test "includes every assign reserved by Phoenix.LiveView" do
      reserved = Resource.lv_reserved_assigns()

      for key <- [:flash, :uploads, :streams, :socket, :myself] do
        assert key in reserved, "expected #{inspect(key)} in lv_reserved_assigns/0"
      end
    end

    test "dropping the reserved set removes :streams from a parent-style assigns map" do
      assigns = %{streams: %{example: :ref}, foo: 1, bar: 2}

      result = Map.drop(assigns, Resource.lv_reserved_assigns())

      refute Map.has_key?(result, :streams)
      assert result == %{foo: 1, bar: 2}
    end
  end

  describe "pagination/1 accessibility" do
    setup do
      html =
        render_component(&Resource.pagination/1,
          current_page: 2,
          total_pages: 10,
          page_path: &"/admin/posts?page=#{&1}"
        )

      %{doc: LazyHTML.from_fragment(html)}
    end

    test "renders the placeholder as non-interactive and hidden from assistive technology", %{doc: doc} do
      assert doc |> LazyHTML.query("button") |> Enum.empty?()

      [placeholder] = doc |> LazyHTML.query(".join-item:not(a)") |> Enum.to_list()
      assert LazyHTML.text(placeholder) =~ "..."
      assert LazyHTML.attribute(placeholder, "aria-hidden") == ["true"]
      assert LazyHTML.attribute(placeholder, "aria-disable") == []
    end

    test "marks only the current page link with aria-current", %{doc: doc} do
      current = LazyHTML.query(doc, ~s(a[aria-current="page"]))

      assert LazyHTML.text(current) =~ "2"
      assert doc |> LazyHTML.query("a[aria-current]") |> Enum.count() == 1
    end
  end
end
