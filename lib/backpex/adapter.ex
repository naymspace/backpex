defmodule Backpex.Adapter do
  @moduledoc ~S"""
  Specification of the datalayer adapter.

  > ### Work in progress {: .warning}
  >
  > The `Backpex.Adapter` behaviour is currently under heavy development and will change drastically in future updates.
  > Backpex started out as `Ecto`-only and this is still deeply embedded in the core. We are working on changing this.
  > Do not rely on the current API to build new adapters, as the callbacks will still change significantly. This will be
  > an iterative process over the next few releases.
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
  @callback get(term(), map(), module()) :: {:ok, struct() | nil} | {:error, term()}

  @doc """
  Returns a list of items by given criteria.
  """
  @callback list(keyword(), map(), module()) :: {:ok, list()}

  @doc """
  Gets the total count of the current live_resource.
  Possibly being constrained the item query and the search- and filter options.
  """
  @callback count(keyword(), map(), module()) :: {:ok, non_neg_integer()}

  @doc """
  Inserts given item.
  """
  @callback insert(struct(), module()) :: {:ok, struct()} | {:error, term()}

  @doc """
  Updates given item.
  """
  @callback update(struct(), module()) :: {:ok, struct()} | {:error, term()}

  @doc """
  Updates given items.
  """
  @callback update_all(list(struct()), keyword(), module()) :: {:ok, non_neg_integer()}

  @doc """
  Applies a change to a given item.
  """
  @callback change(term(), term(), term(), term(), term(), term()) :: term()

  @doc """
  Deletes multiple items.
  """
  @callback delete_all(list(struct()), module()) :: {:ok, term()} | {:error, term()}
end
