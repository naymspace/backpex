defmodule Backpex.PaginationValidationTest do
  use ExUnit.Case, async: true

  alias Backpex.PaginationValidation

  @default_opts [
    per_page_default: 15,
    per_page_options: [15, 50, 100],
    orderable_fields: [:id, :title, :inserted_at],
    init_order: %{by: :id, direction: :asc}
  ]

  describe "build/2" do
    test "returns defaults when params are empty" do
      result = PaginationValidation.build(%{}, @default_opts)

      assert result == %{
               page: 1,
               per_page: 15,
               order_by: :id,
               order_direction: :asc
             }
    end

    test "parses valid integer page" do
      result = PaginationValidation.build(%{"page" => "5"}, @default_opts)
      assert result.page == 5
    end

    test "returns default for invalid page string" do
      result = PaginationValidation.build(%{"page" => "abc"}, @default_opts)
      assert result.page == 1
    end

    test "returns default for negative page" do
      result = PaginationValidation.build(%{"page" => "-5"}, @default_opts)
      assert result.page == 1
    end

    test "returns default for zero page" do
      result = PaginationValidation.build(%{"page" => "0"}, @default_opts)
      assert result.page == 1
    end

    test "parses valid per_page from allowed options" do
      result = PaginationValidation.build(%{"per_page" => "50"}, @default_opts)
      assert result.per_page == 50
    end

    test "returns default for per_page not in options" do
      result = PaginationValidation.build(%{"per_page" => "25"}, @default_opts)
      assert result.per_page == 15
    end

    test "returns default for invalid per_page string" do
      result = PaginationValidation.build(%{"per_page" => "invalid"}, @default_opts)
      assert result.per_page == 15
    end

    test "parses valid order_by from orderable fields" do
      result = PaginationValidation.build(%{"order_by" => "title"}, @default_opts)
      assert result.order_by == :title
    end

    test "returns default for order_by not in orderable fields" do
      result = PaginationValidation.build(%{"order_by" => "nonexistent"}, @default_opts)
      assert result.order_by == :id
    end

    test "returns default for order_by with invalid atom (doesn't crash)" do
      # This would crash with String.to_existing_atom
      result = PaginationValidation.build(%{"order_by" => "totally_random_12345"}, @default_opts)
      assert result.order_by == :id
    end

    test "parses valid order_direction asc" do
      result = PaginationValidation.build(%{"order_direction" => "asc"}, @default_opts)
      assert result.order_direction == :asc
    end

    test "parses valid order_direction desc" do
      result = PaginationValidation.build(%{"order_direction" => "desc"}, @default_opts)
      assert result.order_direction == :desc
    end

    test "returns default for invalid order_direction" do
      result = PaginationValidation.build(%{"order_direction" => "invalid"}, @default_opts)
      assert result.order_direction == :asc
    end

    test "returns default for order_direction with wrong case" do
      result = PaginationValidation.build(%{"order_direction" => "ASC"}, @default_opts)
      assert result.order_direction == :asc
    end

    test "handles all params together" do
      params = %{
        "page" => "3",
        "per_page" => "100",
        "order_by" => "inserted_at",
        "order_direction" => "desc"
      }

      result = PaginationValidation.build(params, @default_opts)

      assert result == %{
               page: 3,
               per_page: 100,
               order_by: :inserted_at,
               order_direction: :desc
             }
    end

    test "uses provided init_order as defaults" do
      opts = Keyword.put(@default_opts, :init_order, %{by: :title, direction: :desc})
      result = PaginationValidation.build(%{}, opts)

      assert result.order_by == :title
      assert result.order_direction == :desc
    end

    test "uses provided per_page_default" do
      opts = Keyword.put(@default_opts, :per_page_default, 50)
      result = PaginationValidation.build(%{}, opts)

      assert result.per_page == 50
    end

    test "rejects page with trailing text (stricter than Integer.parse)" do
      result = PaginationValidation.build(%{"page" => "5abc"}, @default_opts)
      assert result.page == 1
    end

    test "handles integer values (not strings)" do
      params = %{
        "page" => 3,
        "per_page" => 50,
        "order_by" => :title,
        "order_direction" => :desc
      }

      result = PaginationValidation.build(params, @default_opts)
      assert result.page == 3
      assert result.per_page == 50
    end

    test "handles empty string values as missing" do
      params = %{"page" => "", "per_page" => "", "order_by" => "", "order_direction" => ""}
      result = PaginationValidation.build(params, @default_opts)

      assert result == %{
               page: 1,
               per_page: 15,
               order_by: :id,
               order_direction: :asc
             }
    end

    test "handles nil values as missing" do
      params = %{"page" => nil, "per_page" => nil, "order_by" => nil, "order_direction" => nil}
      result = PaginationValidation.build(params, @default_opts)

      assert result == %{
               page: 1,
               per_page: 15,
               order_by: :id,
               order_direction: :asc
             }
    end
  end

  describe "clamp_page/2" do
    test "returns page when within valid range" do
      assert PaginationValidation.clamp_page(3, 5) == 3
    end

    test "returns 1 when page is less than 1" do
      assert PaginationValidation.clamp_page(0, 5) == 1
      assert PaginationValidation.clamp_page(-5, 5) == 1
    end

    test "returns total_pages when page exceeds it" do
      assert PaginationValidation.clamp_page(10, 5) == 5
    end

    test "returns 1 when total_pages is 0" do
      assert PaginationValidation.clamp_page(5, 0) == 1
    end

    test "returns 1 when both page and total_pages are 1" do
      assert PaginationValidation.clamp_page(1, 1) == 1
    end
  end

  describe "security" do
    test "does not create atoms for unknown order_by values" do
      unknown_field = "this_should_not_create_an_atom_xyz123"

      _result =
        PaginationValidation.build(
          %{"order_by" => unknown_field},
          @default_opts
        )

      assert_raise ArgumentError, fn ->
        :erlang.binary_to_existing_atom(unknown_field, :utf8)
      end
    end

    test "does not create atoms for unknown order_direction values" do
      unknown_direction = "ascending_not_an_atom_abc789"

      _result =
        PaginationValidation.build(
          %{"order_direction" => unknown_direction},
          @default_opts
        )

      assert_raise ArgumentError, fn ->
        :erlang.binary_to_existing_atom(unknown_direction, :utf8)
      end
    end
  end
end
