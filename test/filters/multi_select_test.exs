defmodule Backpex.Filters.MultiSelectTest do
  use ExUnit.Case, async: true

  import Ecto.Query
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Backpex.Filters.MultiSelect, as: MultiSelectFilter

  doctest MultiSelectFilter

  defmodule TestItem do
    use Ecto.Schema

    @primary_key {:id, :id, autogenerate: false}
    schema "items" do
      field :status, :string
      field :user_id, :binary_id
      field :category, :string
    end
  end

  describe "query/4" do
    test "returns original query when value is empty list" do
      base_query = from(TestItem)

      query = MultiSelectFilter.query(base_query, :user_id, [], %{})

      assert query == base_query
    end

    test "applies IN condition for single value" do
      base_query = from(TestItem)

      query = MultiSelectFilter.query(base_query, :user_id, ["acdd1860-65ce-4ed6-a37c-433851cf68d7"], %{})

      assert [%{expr: where_expr}] = query.wheres
      assert match?({:in, _, _}, where_expr)
    end

    test "applies IN condition for multiple values" do
      base_query = from(TestItem)
      values = ["acdd1860-65ce-4ed6-a37c-433851cf68d7", "9d78ce5e-9334-4a6c-a076-f1e72522de2"]

      query = MultiSelectFilter.query(base_query, :user_id, values, %{})

      assert [%{expr: where_expr}] = query.wheres
      assert match?({:in, _, _}, where_expr)
    end

    test "works with string values" do
      base_query = from(TestItem)

      query = MultiSelectFilter.query(base_query, :status, ["open", "pending"], %{})

      assert [%{expr: where_expr}] = query.wheres
      assert match?({:in, _, _}, where_expr)
    end

    test "works with different attribute names" do
      base_query = from(TestItem)

      query = MultiSelectFilter.query(base_query, :category, ["electronics", "books"], %{})

      assert [%{expr: where_expr}] = query.wheres
      assert match?({:in, _, _}, where_expr)
    end
  end

  describe "changeset/3" do
    defp test_options do
      [
        {"John Doe", "acdd1860-65ce-4ed6-a37c-433851cf68d7"},
        {"Jane Doe", "9d78ce5e-9334-4a6c-a076-f1e72522de2"},
        {"Bob Smith", :bob}
      ]
    end

    test "validates selected values exist in options (single)" do
      changeset =
        {%{}, %{users: {:array, :string}}}
        |> Ecto.Changeset.cast(%{users: ["acdd1860-65ce-4ed6-a37c-433851cf68d7"]}, [:users])

      result = MultiSelectFilter.changeset(changeset, :users, test_options())

      assert result.valid?
    end

    test "validates selected values exist in options (multiple)" do
      changeset =
        {%{}, %{users: {:array, :string}}}
        |> Ecto.Changeset.cast(
          %{users: ["acdd1860-65ce-4ed6-a37c-433851cf68d7", "9d78ce5e-9334-4a6c-a076-f1e72522de2"]},
          [:users]
        )

      result = MultiSelectFilter.changeset(changeset, :users, test_options())

      assert result.valid?
    end

    test "validates atom options converted to string" do
      changeset =
        {%{}, %{users: {:array, :string}}}
        |> Ecto.Changeset.cast(%{users: ["bob"]}, [:users])

      result = MultiSelectFilter.changeset(changeset, :users, test_options())

      assert result.valid?
    end

    test "returns error for invalid option value" do
      changeset =
        {%{}, %{users: {:array, :string}}}
        |> Ecto.Changeset.cast(%{users: ["invalid-uuid"]}, [:users])

      result = MultiSelectFilter.changeset(changeset, :users, test_options())

      refute result.valid?
      assert Keyword.has_key?(result.errors, :users)
    end

    test "returns error when mix of valid and invalid values" do
      changeset =
        {%{}, %{users: {:array, :string}}}
        |> Ecto.Changeset.cast(
          %{users: ["acdd1860-65ce-4ed6-a37c-433851cf68d7", "invalid-uuid"]},
          [:users]
        )

      result = MultiSelectFilter.changeset(changeset, :users, test_options())

      refute result.valid?
      assert Keyword.has_key?(result.errors, :users)
    end

    test "accepts empty list" do
      changeset =
        {%{}, %{users: {:array, :string}}}
        |> Ecto.Changeset.cast(%{users: []}, [:users])

      result = MultiSelectFilter.changeset(changeset, :users, test_options())

      assert result.valid?
    end

    test "accepts nil value" do
      changeset =
        {%{}, %{users: {:array, :string}}}
        |> Ecto.Changeset.cast(%{}, [:users])

      result = MultiSelectFilter.changeset(changeset, :users, test_options())

      assert result.valid?
    end
  end

  describe "render_form/1" do
    @form_options [{"Open", :open}, {"Closed", :closed}, {"Archived", :archived}]

    test "renders a small combobox for multiple values with the prompt and a search input" do
      document = render_form(prompt: "Select statuses")

      assert attribute(document, "#filters_status", "phx-hook") == ["BackpexCombobox"]
      assert attribute(document, "#filters_status", "data-multiple") == [""]
      assert texts(document, "[data-part=placeholder]:not([hidden])") == ["Select statuses"]
      assert attribute(document, "[role=option]", "data-value") == ["open", "closed", "archived"]
      assert attribute(document, "input[data-part=search]", "id") == ["filters_status-search"]

      [class] = attribute(document, "[data-part=control]", "class")
      assert "input-sm" in String.split(class)
    end

    test "submits an empty value without a selection, so the filter can be cleared" do
      document = render_form(prompt: "Select statuses")

      assert attribute(document, "input[name]", "name") == ["filters[status]"]
      assert attribute(document, "input[name]", "value") == [""]
    end

    test "selects the options of the values and submits them" do
      document = render_form(prompt: "Select statuses", value: ["open", "archived"])

      assert texts(document, "[data-part=badge-label]") == ["Open", "Archived"]
      assert texts(document, "[role=option][aria-selected=true]") == ["Open", "Archived"]
      assert attribute(document, ~s|input[name="filters[status][]"]|, "value") == ["open", "archived"]
    end

    test "is named by the label of the filter, or by the prompt without a label" do
      assert [prompt: "Select statuses", label: "Status"]
             |> render_form()
             |> attribute("#filters_status-trigger", "aria-label") == ["Status"]

      assert [prompt: "Select statuses"] |> render_form() |> attribute("#filters_status-trigger", "aria-label") ==
               ["Select statuses"]
    end

    test "has no search input when it is not searchable" do
      document = render_form(prompt: "Select statuses", searchable: false)

      assert document |> LazyHTML.query("input[data-part=search]") |> Enum.empty?()
    end

    test "shows the errors of the filter" do
      document = render_form(prompt: "Select statuses", errors: ["contains invalid options"])

      assert texts(document, "#filters_status-errors p") == ["contains invalid options"]
      assert attribute(document, "#filters_status-trigger", "aria-invalid") == ["true"]
    end
  end

  defp render_form(assigns) do
    assigns =
      Keyword.merge(
        [form: Phoenix.Component.to_form(%{}, as: :filters), field: :status, value: nil, options: @form_options],
        assigns
      )

    (&MultiSelectFilter.render_form/1) |> render_component(assigns) |> LazyHTML.from_fragment()
  end

  defp texts(document, selector) do
    document |> LazyHTML.query(selector) |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))
  end

  defp attribute(document, selector, name), do: document |> LazyHTML.query(selector) |> LazyHTML.attribute(name)
end
