defmodule Backpex.Adapter do
  @moduledoc ~S"""
  Specification of the datalayer adapter.
  """

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @config_schema opts[:config_schema] || []

      @behaviour Backpex.Adapter

      def validate_config!(config) do
        NimbleOptions.validate!(config, @config_schema)
      end
    end
  end

  @doc """
  Gets a database record with the given primary key value.

  Should return `nil` if no result was found.
  """
  @callback get(term(), term(), term(), term()) :: term()

  @doc """
  Gets a database record with the given primary key value.

  Should raise an exception if no result was found.
  """
  @callback get!(term(), term(), term(), term()) :: term()

  @doc """
  Deletes multiple items.
  """
  @callback delete_all(list(), term()) :: {:ok, term()} | {:error, term()}
end
