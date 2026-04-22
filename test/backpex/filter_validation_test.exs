defmodule Backpex.FilterValidationTest do
  use ExUnit.Case, async: true

  alias Backpex.FilterValidation

  # Test filter module with string type
  defmodule StringFilter do
    @moduledoc false
    use Backpex.Filter

    @impl Backpex.Filter
    def label, do: "String Filter"

    @impl Backpex.Filter
    def type(_assigns), do: :string

    @impl Backpex.Filter
    def render(assigns), do: assigns

    @impl Backpex.Filter
    def render_form(assigns), do: assigns
  end

  # Test filter module with array type
  defmodule ArrayFilter do
    @moduledoc false
    use Backpex.Filter

    @impl Backpex.Filter
    def label, do: "Array Filter"

    @impl Backpex.Filter
    def type(_assigns), do: {:array, :string}

    @impl Backpex.Filter
    def render(assigns), do: assigns

    @impl Backpex.Filter
    def render_form(assigns), do: assigns
  end

  # Test filter module with map type (like Range)
  defmodule MapFilter do
    @moduledoc false
    use Backpex.Filter

    @impl Backpex.Filter
    def label, do: "Map Filter"

    @impl Backpex.Filter
    def type(_assigns), do: :map

    @impl Backpex.Filter
    def render(assigns), do: assigns

    @impl Backpex.Filter
    def render_form(assigns), do: assigns
  end

  # Test filter with custom validation
  defmodule ValidatingFilter do
    @moduledoc false
    use Backpex.Filter

    @impl Backpex.Filter
    def label, do: "Validating Filter"

    @impl Backpex.Filter
    def type(_assigns), do: :integer

    @impl Backpex.Filter
    def changeset(changeset, field, _assigns) do
      Ecto.Changeset.validate_number(changeset, field, greater_than: 0)
    end

    @impl Backpex.Filter
    def render(assigns), do: assigns

    @impl Backpex.Filter
    def render_form(assigns), do: assigns
  end

  describe "build_changeset/3" do
    test "builds changeset from empty params" do
      filter_configs = [status: %{module: StringFilter}]

      changeset = FilterValidation.build_changeset(%{}, filter_configs, %{})

      assert changeset.valid?
      assert changeset.changes == %{}
    end

    test "builds changeset from string params" do
      filter_configs = [status: %{module: StringFilter}]
      params = %{"status" => "active"}

      changeset = FilterValidation.build_changeset(params, filter_configs, %{})

      assert changeset.valid?
      assert changeset.changes == %{status: "active"}
    end

    test "builds changeset from atom params" do
      filter_configs = [status: %{module: StringFilter}]
      params = %{status: "active"}

      changeset = FilterValidation.build_changeset(params, filter_configs, %{})

      assert changeset.valid?
      assert changeset.changes == %{status: "active"}
    end

    test "handles array type filters" do
      filter_configs = [tags: %{module: ArrayFilter}]
      params = %{"tags" => ["a", "b", "c"]}

      changeset = FilterValidation.build_changeset(params, filter_configs, %{})

      assert changeset.valid?
      assert changeset.changes == %{tags: ["a", "b", "c"]}
    end

    test "handles map type filters" do
      filter_configs = [date_range: %{module: MapFilter}]
      params = %{"date_range" => %{"start" => "2024-01-01", "end" => "2024-12-31"}}

      changeset = FilterValidation.build_changeset(params, filter_configs, %{})

      assert changeset.valid?
      assert changeset.changes == %{date_range: %{"start" => "2024-01-01", "end" => "2024-12-31"}}
    end

    test "applies filter-specific validation" do
      filter_configs = [count: %{module: ValidatingFilter}]
      params = %{"count" => "-5"}

      changeset = FilterValidation.build_changeset(params, filter_configs, %{})

      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :count)
    end

    test "handles multiple filters" do
      filter_configs = [
        status: %{module: StringFilter},
        tags: %{module: ArrayFilter},
        count: %{module: ValidatingFilter}
      ]

      params = %{"status" => "active", "tags" => ["a", "b"], "count" => "10"}

      changeset = FilterValidation.build_changeset(params, filter_configs, %{})

      assert changeset.valid?
      assert changeset.changes == %{status: "active", tags: ["a", "b"], count: 10}
    end

    test "ignores unknown params" do
      filter_configs = [status: %{module: StringFilter}]
      params = %{"status" => "active", "unknown_filter" => "value"}

      changeset = FilterValidation.build_changeset(params, filter_configs, %{})

      assert changeset.valid?
      assert changeset.changes == %{status: "active"}
    end

    test "normalizes empty string to nil" do
      filter_configs = [status: %{module: StringFilter}]
      params = %{"status" => ""}

      changeset = FilterValidation.build_changeset(params, filter_configs, %{})

      assert changeset.valid?
      # Empty string normalized to nil, which doesn't appear in changes
      assert changeset.changes == %{}
    end
  end

  describe "valid_values/1" do
    test "returns all changes when changeset is valid" do
      filter_configs = [status: %{module: StringFilter}, tags: %{module: ArrayFilter}]
      params = %{"status" => "active", "tags" => ["a"]}

      changeset = FilterValidation.build_changeset(params, filter_configs, %{})
      result = FilterValidation.valid_values(changeset)

      assert result == %{status: "active", tags: ["a"]}
    end

    test "excludes fields with errors" do
      filter_configs = [
        status: %{module: StringFilter},
        count: %{module: ValidatingFilter}
      ]

      params = %{"status" => "active", "count" => "-5"}

      changeset = FilterValidation.build_changeset(params, filter_configs, %{})
      result = FilterValidation.valid_values(changeset)

      assert result == %{status: "active"}
      refute Map.has_key?(result, :count)
    end

    test "excludes empty values" do
      filter_configs = [status: %{module: StringFilter}, other: %{module: StringFilter}]
      params = %{"status" => "active", "other" => ""}

      changeset = FilterValidation.build_changeset(params, filter_configs, %{})
      result = FilterValidation.valid_values(changeset)

      assert result == %{status: "active"}
    end

    test "excludes empty array values" do
      filter_configs = [status: %{module: StringFilter}, tags: %{module: ArrayFilter}]
      params = %{"status" => "active", "tags" => []}

      changeset = FilterValidation.build_changeset(params, filter_configs, %{})
      result = FilterValidation.valid_values(changeset)

      assert result == %{status: "active"}
    end

    test "excludes empty range values with string keys" do
      filter_configs = [date_range: %{module: MapFilter}]
      params = %{"date_range" => %{"start" => "", "end" => ""}}

      changeset = FilterValidation.build_changeset(params, filter_configs, %{})
      result = FilterValidation.valid_values(changeset)

      assert result == %{}
    end

    test "includes partial range values" do
      filter_configs = [date_range: %{module: MapFilter}]
      params = %{"date_range" => %{"start" => "2024-01-01", "end" => ""}}

      changeset = FilterValidation.build_changeset(params, filter_configs, %{})
      result = FilterValidation.valid_values(changeset)

      assert result == %{date_range: %{"start" => "2024-01-01", "end" => ""}}
    end
  end

  describe "build_types/2" do
    test "builds types map from filter configs" do
      filter_configs = [
        status: %{module: StringFilter},
        tags: %{module: ArrayFilter},
        count: %{module: ValidatingFilter}
      ]

      types = FilterValidation.build_types(filter_configs, %{})

      assert types == %{
               status: :string,
               tags: {:array, :string},
               count: :integer
             }
    end

    test "returns empty map for empty configs" do
      types = FilterValidation.build_types([], %{})

      assert types == %{}
    end
  end
end
