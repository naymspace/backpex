defmodule Backpex.QueryOptionsValidation do
  @moduledoc """
  Validates query options (pagination and sorting) from URL params.

  This module provides validation for pagination and sorting parameters,
  ensuring invalid URL params don't crash the application and fall back
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
  Builds validated query options from URL params.

  Returns a map with validated pagination and sorting options.
  Invalid values are replaced with defaults.

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
      iex> Backpex.QueryOptionsValidation.build(params, opts)
      %{page: 2, per_page: 50, order_by: :title, order_direction: :desc}

      # Invalid values fall back to defaults
      iex> params = %{"page" => "invalid", "order_by" => "nonexistent"}
      iex> opts = [per_page_default: 15, per_page_options: [15, 50, 100], orderable_fields: [:id, :title], init_order: %{by: :id, direction: :asc}]
      iex> Backpex.QueryOptionsValidation.build(params, opts)
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

    # Validate pagination using Ecto changeset
    pagination = validate_pagination(params, per_page_default, per_page_options)

    # Validate sorting (atoms handled separately to avoid Ecto atom casting issues)
    sorting = validate_sorting(params, orderable_fields, init_order)

    Map.merge(defaults, pagination) |> Map.merge(sorting)
  end

  @doc """
  Clamps a page number to valid range based on total pages.

  This is called after the initial validation once we know the total item count.

  ## Examples

      iex> Backpex.QueryOptionsValidation.clamp_page(5, 3)
      3
      iex> Backpex.QueryOptionsValidation.clamp_page(2, 5)
      2
      iex> Backpex.QueryOptionsValidation.clamp_page(-1, 5)
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

  # Validates pagination params (page, per_page) using Ecto changeset
  defp validate_pagination(params, per_page_default, per_page_options) do
    types = %{page: :integer, per_page: :integer}
    defaults = %{page: 1, per_page: per_page_default}

    # Filter out empty/nil values so Ecto treats them as missing (uses defaults)
    filtered = Map.reject(params, fn {_k, v} -> v in [nil, ""] end)

    changeset =
      {defaults, types}
      |> cast(filtered, [:page, :per_page])
      |> validate_number(:page, greater_than: 0)
      |> validate_inclusion(:per_page, per_page_options)

    extract_valid_values(changeset, defaults)
  end

  # Validates sorting params (order_by, order_direction)
  # Handles atom conversion safely without using Ecto atom types
  defp validate_sorting(params, orderable_fields, init_order) do
    order_by = safe_get_atom(params, "order_by", orderable_fields, init_order.by)
    order_direction = safe_get_atom(params, "order_direction", @permitted_directions, init_order.direction)

    %{order_by: order_by, order_direction: order_direction}
  end

  # Safely gets an atom value from params, validating against allowed values
  # Returns default if the value is missing, invalid, or not in allowed list
  defp safe_get_atom(params, string_key, allowed_atoms, default) do
    case Map.get(params, string_key) do
      nil ->
        default

      "" ->
        default

      value when is_binary(value) ->
        # Only convert to atom if it matches an allowed value
        # This prevents atom exhaustion attacks
        case safe_to_atom(value, allowed_atoms) do
          nil -> default
          atom -> atom
        end

      value when is_atom(value) ->
        if value in allowed_atoms, do: value, else: default

      _other ->
        default
    end
  end

  # Safely converts a string to an atom only if it matches an allowed value.
  # Returns nil if the string doesn't match any allowed atom.
  defp safe_to_atom(string, allowed_atoms) do
    Enum.find(allowed_atoms, fn allowed ->
      Atom.to_string(allowed) == string
    end)
  end

  # Extracts valid values from changeset, using defaults for invalid fields.
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
