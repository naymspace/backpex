defmodule Backpex.PaginationValidation do
  @moduledoc """
  Validates pagination and sorting parameters from URL params.

  Ensures invalid URL params don't crash the application and fall back
  to sensible defaults.

  ## Validated Parameters

    * `page` - Page number (positive integer, defaults to 1)
    * `per_page` - Items per page (must be in allowed options)
    * `order_by` - Field to sort by (must be in orderable fields)
    * `order_direction` - Sort direction (must be :asc or :desc)

  """

  import Ecto.Changeset

  @permitted_directions [:asc, :desc]

  @doc """
  Builds validated pagination and sorting options from URL params.

  Returns a map with validated values. Invalid values are replaced with defaults.

  ## Parameters

    * `params` - Map of URL params (string keys)
    * `opts` - Keyword list with:
      * `:per_page_default` - Default items per page (required)
      * `:per_page_options` - List of allowed per_page values (required)
      * `:orderable_fields` - List of field atoms that can be sorted (required)
      * `:init_order` - Map with `:by` and `:direction` defaults (required)

  ## Returns

  A map with validated values:

      %{
        page: integer(),
        per_page: integer(),
        order_by: atom(),
        order_direction: :asc | :desc
      }

  ## Examples

      iex> params = %{"page" => "2", "per_page" => "50", "order_by" => "title", "order_direction" => "desc"}
      iex> opts = [
      ...>   per_page_default: 15,
      ...>   per_page_options: [15, 50, 100],
      ...>   orderable_fields: [:id, :title, :inserted_at],
      ...>   init_order: %{by: :id, direction: :asc}
      ...> ]
      iex> Backpex.PaginationValidation.build(params, opts)
      %{page: 2, per_page: 50, order_by: :title, order_direction: :desc}

      # Invalid values fall back to defaults
      iex> params = %{"page" => "invalid", "order_by" => "nonexistent"}
      iex> opts = [per_page_default: 15, per_page_options: [15, 50, 100], orderable_fields: [:id, :title], init_order: %{by: :id, direction: :asc}]
      iex> Backpex.PaginationValidation.build(params, opts)
      %{page: 1, per_page: 15, order_by: :id, order_direction: :asc}

  """
  def build(params, opts) do
    per_page_default = Keyword.fetch!(opts, :per_page_default)
    per_page_options = Keyword.fetch!(opts, :per_page_options)
    orderable_fields = Keyword.fetch!(opts, :orderable_fields)
    init_order = Keyword.fetch!(opts, :init_order)

    defaults = %{
      page: 1,
      per_page: per_page_default,
      order_by: init_order.by,
      order_direction: init_order.direction
    }

    pagination = validate_pagination(params, per_page_default, per_page_options)
    sorting = validate_sorting(params, orderable_fields, init_order)

    Map.merge(defaults, pagination) |> Map.merge(sorting)
  end

  @doc """
  Clamps a page number to valid range based on total pages.

  This is called after the initial validation once we know the total item count.

  ## Examples

      iex> Backpex.PaginationValidation.clamp_page(5, 3)
      3
      iex> Backpex.PaginationValidation.clamp_page(2, 5)
      2
      iex> Backpex.PaginationValidation.clamp_page(-1, 5)
      1

  """
  def clamp_page(_page, 0), do: 1

  def clamp_page(page, total_pages) do
    cond do
      page < 1 -> 1
      page > total_pages -> total_pages
      true -> page
    end
  end

  defp validate_pagination(params, per_page_default, per_page_options) do
    types = %{page: :integer, per_page: :integer}
    defaults = %{page: 1, per_page: per_page_default}

    filtered = Map.reject(params, fn {_k, v} -> v in [nil, ""] end)

    changeset =
      {defaults, types}
      |> cast(filtered, [:page, :per_page])
      |> validate_number(:page, greater_than: 0)
      |> validate_inclusion(:per_page, per_page_options)

    extract_valid_values(changeset, defaults)
  end

  defp validate_sorting(params, orderable_fields, init_order) do
    order_by = find_allowed_atom(params["order_by"], orderable_fields, init_order.by)
    order_direction = find_allowed_atom(params["order_direction"], @permitted_directions, init_order.direction)

    %{order_by: order_by, order_direction: order_direction}
  end

  defp find_allowed_atom(nil, _allowed, default), do: default
  defp find_allowed_atom("", _allowed, default), do: default

  defp find_allowed_atom(value, allowed, default) when is_binary(value) do
    Enum.find(allowed, default, &(Atom.to_string(&1) == value))
  end

  defp find_allowed_atom(value, allowed, default) when is_atom(value) do
    if value in allowed, do: value, else: default
  end

  defp find_allowed_atom(_value, _allowed, default), do: default

  defp extract_valid_values(changeset, defaults) do
    error_fields = Keyword.keys(changeset.errors) |> MapSet.new()

    Enum.reduce(defaults, %{}, fn {field, default}, acc ->
      value =
        if MapSet.member?(error_fields, field) do
          default
        else
          Map.get(changeset.changes, field, default)
        end

      Map.put(acc, field, value)
    end)
  end
end
