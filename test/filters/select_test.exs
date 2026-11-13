defmodule Backpex.Filters.SelectTest do
  use ExUnit.Case, async: true

  import Ecto.Query
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Backpex.Filters.Select, as: SelectFilter

  doctest SelectFilter

  defmodule TestItem do
    use Ecto.Schema

    @primary_key {:id, :id, autogenerate: false}
    schema "items" do
      field :status, :string
      field :category, :string
      field :priority, :integer
    end
  end

  describe "query/4" do
    test "applies equality condition for attribute" do
      base_query = from(TestItem)

      query = SelectFilter.query(base_query, :status, "open", %{})

      assert [%{expr: where_expr}] = query.wheres
      assert match?({:==, _, _}, where_expr)
    end

    test "works with string values" do
      base_query = from(TestItem)

      query = SelectFilter.query(base_query, :category, "electronics", %{})

      assert [%{expr: where_expr}] = query.wheres
      assert match?({:==, _, _}, where_expr)
    end

    test "works with different attribute names" do
      base_query = from(TestItem)

      query = SelectFilter.query(base_query, :priority, 1, %{})

      assert [%{expr: where_expr}] = query.wheres
      assert match?({:==, _, _}, where_expr)
    end
  end

  describe "changeset/3" do
    defp test_options do
      [{"Open", :open}, {"Closed", :closed}, {"Pending", "pending"}]
    end

    test "validates selected value exists in options (atom)" do
      changeset = {%{}, %{status: :string}} |> Ecto.Changeset.cast(%{status: "open"}, [:status])

      result = SelectFilter.changeset(changeset, :status, test_options())

      assert result.valid?
    end

    test "validates selected value exists in options (string)" do
      changeset = {%{}, %{status: :string}} |> Ecto.Changeset.cast(%{status: "pending"}, [:status])

      result = SelectFilter.changeset(changeset, :status, test_options())

      assert result.valid?
    end

    test "returns error for invalid option value" do
      changeset = {%{}, %{status: :string}} |> Ecto.Changeset.cast(%{status: "invalid"}, [:status])

      result = SelectFilter.changeset(changeset, :status, test_options())

      refute result.valid?
      assert Keyword.has_key?(result.errors, :status)
    end

    test "accepts nil value" do
      changeset = {%{}, %{status: :string}} |> Ecto.Changeset.cast(%{}, [:status])

      result = SelectFilter.changeset(changeset, :status, test_options())

      assert result.valid?
    end

    test "accepts empty string value" do
      changeset = {%{}, %{status: :string}} |> Ecto.Changeset.cast(%{status: ""}, [:status])

      result = SelectFilter.changeset(changeset, :status, test_options())

      assert result.valid?
    end
  end

  describe "render_form/1" do
    @form_options [{"Open", :open}, {"Closed", :closed}]

    test "renders a small combobox with the prompt and a clear button" do
      document = render_form(prompt: "Select a status")

      assert attribute(document, "#filters_status", "phx-hook") == ["BackpexCombobox"]
      assert attribute(document, "#filters_status", "data-multiple") == []
      assert attribute(document, "input[data-part=anchor]", "name") == ["filters[status]"]
      assert attribute(document, "input[data-part=anchor]", "value") == [""]
      assert texts(document, "[data-part=placeholder]:not([hidden])") == ["Select a status"]
      assert document |> LazyHTML.query("[data-part=clear]") |> Enum.count() == 1
      assert attribute(document, "[role=option]", "data-value") == ["open", "closed"]

      [class] = attribute(document, "[data-part=control]", "class")
      assert "input-sm" in String.split(class)
    end

    test "selects the option of the value" do
      document = render_form(prompt: "Select a status", value: "closed")

      assert attribute(document, "input[data-part=anchor]", "value") == ["closed"]
      assert texts(document, "[data-part=value-label]") == ["Closed"]
      assert texts(document, "[role=option][aria-selected=true]") == ["Closed"]
    end

    test "is named by the label of the filter, or by the prompt without a label" do
      assert [prompt: "Select a status", label: "Status"]
             |> render_form()
             |> attribute("#filters_status-trigger", "aria-label") == ["Status"]

      assert [prompt: "Select a status"] |> render_form() |> attribute("#filters_status-trigger", "aria-label") ==
               ["Select a status"]
    end

    test "has a search input only when searchable" do
      assert [prompt: "Select"] |> render_form() |> LazyHTML.query("input[data-part=search]") |> Enum.empty?()
      assert [prompt: "Select", searchable: true] |> render_form() |> attribute("input[data-part=search]", "id") != []
    end

    test "shows the errors of the filter" do
      document = render_form(prompt: "Select", errors: ["is not a valid option"])

      assert texts(document, "#filters_status-errors p") == ["is not a valid option"]
      assert attribute(document, "#filters_status-trigger", "aria-invalid") == ["true"]
    end
  end

  defp render_form(assigns) do
    assigns =
      Keyword.merge(
        [form: Phoenix.Component.to_form(%{}, as: :filters), field: :status, value: nil, options: @form_options],
        assigns
      )

    (&SelectFilter.render_form/1) |> render_component(assigns) |> LazyHTML.from_fragment()
  end

  defp texts(document, selector) do
    document |> LazyHTML.query(selector) |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))
  end

  defp attribute(document, selector, name), do: document |> LazyHTML.query(selector) |> LazyHTML.attribute(name)
end
