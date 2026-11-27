defmodule Backpex.Fields.BelongsToTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Backpex.Fields.BelongsTo
  alias Phoenix.LiveComponent.CID

  defmodule CategoryLive do
    @moduledoc false
    def config(:primary_key), do: :id
    def translate({msg, _opts}), do: msg
  end

  # With `query_limit`, the component loads the options into its assigns, so the render gets them from there.
  @search_assigns [
    options: [{"Anna", 1}, {"Bert", 2}],
    selected_option: nil,
    default_option: {"Anna", 1},
    show_more: false
  ]

  describe "render_form/1 with query_limit" do
    test "searches the options on the server and shows the current value that is on no loaded page" do
      document = render_form([query_limit: 2], value: 3, selected_option: {"Carl", 3})
      root = LazyHTML.query(document, "#change_category_id")

      assert LazyHTML.attribute(root, "data-on-search") == ["search"]
      assert LazyHTML.attribute(root, "phx-target") == ["1"]
      assert document |> LazyHTML.query("#change_category_id-search") |> Enum.any?()
      assert document |> LazyHTML.query("[role=option]") |> LazyHTML.attribute("data-value") == ["1", "2"]
      assert document |> LazyHTML.query("[data-part=value-label]") |> LazyHTML.text() == "Carl"
      assert document |> LazyHTML.query("#change_category_id-anchor") |> LazyHTML.attribute("value") == ["3"]
    end

    test "renders show more below the options while there are more options to load" do
      refute [query_limit: 2] |> render_form(show_more: false) |> show_more_button() |> Enum.any?()

      button = [query_limit: 2] |> render_form(show_more: true) |> show_more_button()

      assert LazyHTML.text(button) =~ "Show more"
      assert LazyHTML.attribute(button, "type") == ["button"]
      assert LazyHTML.attribute(button, "phx-target") == ["1"]
    end

    # A search replaces the options, but the default stays the first option of the options query.
    test "selects the first option of the options query without a prompt and a value" do
      document = render_form([query_limit: 2], value: nil, options: [{"Carl", 3}])

      assert document |> LazyHTML.query("#change_category_id-anchor") |> LazyHTML.attribute("value") == ["1"]
      assert document |> LazyHTML.query("[data-part=value-label]") |> LazyHTML.text() == "Anna"
    end

    test "selects no option with a prompt and without a value" do
      document = render_form([query_limit: 2, prompt: "Choose a category"], value: nil)

      assert document |> LazyHTML.query("#change_category_id-anchor") |> LazyHTML.attribute("value") == [""]
      assert document |> LazyHTML.query("[data-part=placeholder]") |> LazyHTML.text() =~ "Choose a category"
    end

    test "has a search input even without searchable_options" do
      document = render_form([query_limit: 2, searchable_options: false], value: 1)

      assert document |> LazyHTML.query("#change_category_id-search") |> Enum.any?()
    end
  end

  describe "render_index_form/1 with query_limit" do
    test "searches the options on the server and renders show more" do
      field_options = field_options(query_limit: 2, index_editable: true)

      assigns =
        [
          name: :category,
          field_options: field_options,
          item: %{id: 7},
          value: %{id: 3},
          live_resource: CategoryLive,
          related_key: :id,
          readonly: false,
          myself: %CID{cid: 1}
        ] ++ Keyword.merge(@search_assigns, selected_option: {"Carl", 3}, show_more: true)

      document = (&BelongsTo.render_index_form/1) |> render_component(assigns) |> LazyHTML.from_fragment()
      root = LazyHTML.query(document, "#index-form-input-category-7")

      assert LazyHTML.attribute(root, "data-on-search") == ["search"]
      assert LazyHTML.attribute(root, "phx-target") == ["1"]
      assert document |> LazyHTML.query("[data-part=value-label]") |> LazyHTML.text() == "Carl"
      assert document |> show_more_button() |> LazyHTML.attribute("phx-target") == ["1"]
    end
  end

  defp render_form(options, assigns) do
    {value, assigns} = Keyword.pop(assigns, :value)

    assigns =
      [
        name: :category,
        field_options: field_options(options),
        form: Phoenix.Component.to_form(%{"category_id" => value}, as: :change),
        live_resource: CategoryLive,
        owner_key: :category_id,
        readonly: false,
        hide_label: false,
        myself: %CID{cid: 1}
      ] ++ Keyword.merge(@search_assigns, assigns)

    (&BelongsTo.render_form/1)
    |> render_component(assigns)
    |> LazyHTML.from_fragment()
  end

  # Validates the options like a LiveResource does, so the field's config schema must accept them.
  defp field_options(options) do
    {:category, [module: BelongsTo, label: "Category", display_field: :name] ++ options}
    |> BelongsTo.validate_config!(__MODULE__)
    |> Map.new()
  end

  defp show_more_button(document), do: LazyHTML.query(document, ~s|button[phx-click="show-more"]|)
end
