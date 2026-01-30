defmodule Backpex.FilterValidation do
  @moduledoc """
  Builds and validates filter changesets from URL params.

  This module provides the core validation infrastructure for Backpex filters,
  using Ecto changesets to validate filter values before they are applied to queries.
  """

  import Ecto.Changeset

  @doc """
  Builds a changeset from filter params and configurations.

  Returns a changeset that can be used with `Phoenix.Component.to_form/2`.
  The changeset includes all filter values, with validation errors for invalid ones.

  ## Parameters

    * `params` - Map of filter params from URL (e.g., `%{"status" => "active", "date_range" => %{"start" => "2024-01-01"}}`)
    * `filter_configs` - Keyword list of filter configurations from the LiveResource
    * `assigns` - Socket assigns for context (used by filters that need runtime data)

  ## Examples

      iex> filter_configs = [status: %{module: MyFilters.StatusSelect}]
      iex> params = %{"status" => "active"}
      iex> changeset = Backpex.FilterValidation.build_changeset(params, filter_configs, %{})
      iex> changeset.valid?
      true

  """
  def build_changeset(params, filter_configs, assigns) do
    types = build_types(filter_configs, assigns)

    {%{}, types}
    |> cast(normalize_empty_strings(params), Map.keys(types))
    |> apply_filter_changesets(filter_configs, assigns)
  end

  @doc """
  Extracts valid filter values from a changeset.

  Returns a map containing only the filters that passed validation.
  Filters with errors are excluded from the result.

  ## Parameters

    * `changeset` - An Ecto changeset built by `build_changeset/3`

  ## Examples

      iex> changeset = %Ecto.Changeset{changes: %{status: "active", count: 5}, errors: [count: {"is invalid", []}]}
      iex> Backpex.FilterValidation.valid_values(changeset)
      %{status: "active"}

  """
  def valid_values(changeset) do
    error_fields = Keyword.keys(changeset.errors) |> MapSet.new()

    changeset.changes
    |> Enum.reject(fn {field, value} ->
      MapSet.member?(error_fields, field) or empty_value?(value)
    end)
    |> Map.new()
  end

  @doc """
  Builds the types map for schemaless changeset from filter configurations.

  Each filter module must implement `type/1` to specify its Ecto type.
  """
  def build_types(filter_configs, assigns) do
    Enum.reduce(filter_configs, %{}, fn {key, filter}, acc ->
      type = filter.module.type(assigns)
      Map.put(acc, key, type)
    end)
  end

  defp normalize_empty_strings(params) when is_map(params) do
    Map.new(params, fn {key, value} -> {key, normalize_value(value)} end)
  end

  defp normalize_empty_strings(_params), do: %{}

  defp normalize_value(""), do: nil
  defp normalize_value(value), do: value

  defp apply_filter_changesets(changeset, filter_configs, assigns) do
    Enum.reduce(filter_configs, changeset, fn {key, filter}, cs ->
      filter.module.changeset(cs, key, assigns)
    end)
  end

  defp empty_value?(nil), do: true
  defp empty_value?(""), do: true
  defp empty_value?([]), do: true

  defp empty_value?(%{"start" => start_val, "end" => end_val}) when start_val in ["", nil] and end_val in ["", nil],
    do: true

  defp empty_value?(_value), do: false
end
