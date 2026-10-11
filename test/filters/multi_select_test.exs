defmodule Backpex.Filters.MultiSelectTest do
  use ExUnit.Case, async: true

  alias Backpex.Filters.MultiSelect, as: MultiSelectFilter

  doctest MultiSelectFilter

  describe "condition/3" do
    test "returns nil when no value is selected" do
      assert MultiSelectFilter.condition(:user_id, [], %{}) == nil
    end

    test "keeps the items whose field has one of the values" do
      values = ["acdd1860-65ce-4ed6-a37c-433851cf68d7", "9d78ce5e-9334-4a6c-a076-f1e72522de2"]

      assert MultiSelectFilter.condition(:user_id, values, %{}) == {:in, :user_id, values}
      assert MultiSelectFilter.condition(:status, ["open"], %{}) == {:in, :status, ["open"]}
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
end
