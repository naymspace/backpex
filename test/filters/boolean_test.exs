defmodule Backpex.Filters.BooleanTest do
  use ExUnit.Case, async: true

  import Backpex.Expr, only: [expr: 1]

  alias Backpex.Filters.Boolean, as: BooleanFilter

  doctest BooleanFilter

  defmodule OwnerFilter do
    use Backpex.Filters.Boolean

    @impl Backpex.Filter
    def label, do: "Owner"

    @impl Backpex.Filters.Boolean
    def options(assigns), do: [%{label: "Mine", key: "mine", predicate: expr(user_id == ^assigns.user_id)}]
  end

  defp test_options do
    [
      %{label: "Published", key: "published", predicate: expr(published == true)},
      %{label: "Not published", key: "not_published", predicate: expr(published == false)},
      %{label: "Featured", key: "featured", predicate: expr(featured == true)}
    ]
  end

  describe "condition/3" do
    test "returns nil when no option is selected" do
      assert BooleanFilter.condition({:published, %{options: test_options()}}, [], %{}) == nil
    end

    test "returns the predicate of a single selected option" do
      assert BooleanFilter.condition({:published, %{options: test_options()}}, ["published"], %{}) ==
               expr(published == true)
    end

    test "combines the predicates of several selected options with :or" do
      keys = ["published", "not_published", "featured"]

      assert BooleanFilter.condition({:published, %{options: test_options()}}, keys, %{}) ==
               expr(published == true or published == false or featured == true)
    end

    test "finds the predicates of options with atom keys" do
      options = [
        %{label: "Published", key: :published, predicate: expr(published == true)},
        %{label: "Featured", key: :featured, predicate: expr(featured == true)}
      ]

      assert BooleanFilter.condition({:status, %{options: options}}, ["published"], %{}) == expr(published == true)

      assert BooleanFilter.condition({:status, %{options: options}}, ["published", "featured"], %{}) ==
               expr(published == true or featured == true)
    end

    test "ignores selected keys without an option" do
      assert BooleanFilter.condition({:published, %{options: test_options()}}, ["featured", "unknown"], %{}) ==
               expr(featured == true)
    end

    test "returns nil when no selected key has an option" do
      assert BooleanFilter.condition({:published, %{options: test_options()}}, ["unknown", "other"], %{}) == nil
    end

    test "is the condition of a filter module, with the options for the assigns" do
      filter = Backpex.Filter.validate_config!({:owner, %{module: OwnerFilter}}, __MODULE__)

      assert OwnerFilter.condition(
               filter,
               ["mine"],
               %{user_id: 1}
             ) == expr(user_id == 1)
    end
  end

  describe "changeset/3" do
    test "validates selected keys exist in options" do
      changeset = {%{}, %{filter: {:array, :string}}} |> Ecto.Changeset.cast(%{filter: ["published"]}, [:filter])

      result = BooleanFilter.changeset(changeset, {:filter, %{options: test_options()}}, %{})

      assert result.valid?
    end

    test "validates multiple selected keys exist in options" do
      changeset =
        {%{}, %{filter: {:array, :string}}}
        |> Ecto.Changeset.cast(%{filter: ["published", "featured"]}, [:filter])

      result = BooleanFilter.changeset(changeset, {:filter, %{options: test_options()}}, %{})

      assert result.valid?
    end

    test "returns error for invalid option key" do
      changeset =
        {%{}, %{filter: {:array, :string}}}
        |> Ecto.Changeset.cast(%{filter: ["invalid_key"]}, [:filter])

      result = BooleanFilter.changeset(changeset, {:filter, %{options: test_options()}}, %{})

      refute result.valid?
      assert Keyword.has_key?(result.errors, :filter)
    end

    test "returns error when mix of valid and invalid keys" do
      changeset =
        {%{}, %{filter: {:array, :string}}}
        |> Ecto.Changeset.cast(%{filter: ["published", "invalid_key"]}, [:filter])

      result = BooleanFilter.changeset(changeset, {:filter, %{options: test_options()}}, %{})

      refute result.valid?
      assert Keyword.has_key?(result.errors, :filter)
    end

    test "accepts empty list" do
      changeset =
        {%{}, %{filter: {:array, :string}}}
        |> Ecto.Changeset.cast(%{filter: []}, [:filter])

      result = BooleanFilter.changeset(changeset, {:filter, %{options: test_options()}}, %{})

      assert result.valid?
    end

    test "accepts nil value" do
      changeset =
        {%{}, %{filter: {:array, :string}}}
        |> Ecto.Changeset.cast(%{}, [:filter])

      result = BooleanFilter.changeset(changeset, {:filter, %{options: test_options()}}, %{})

      assert result.valid?
    end
  end
end
