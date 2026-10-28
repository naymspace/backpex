defmodule Backpex.Test.ReadOnlyAdapter do
  @moduledoc """
  `Backpex.Adapters.Memory` without writes: it supports no feature (see `c:Backpex.Adapter.supports?/2`), like a data
  source that can only be read.
  """
  @behaviour Backpex.Adapter

  alias Backpex.Adapters.Memory

  def validate_config!(config), do: Memory.validate_config!(config)

  @impl Backpex.Adapter
  def supports?(_live_resource, _feature), do: false

  @impl Backpex.Adapter
  defdelegate read(query), to: Memory

  @impl Backpex.Adapter
  defdelegate describe(path, live_resource), to: Memory

  @impl Backpex.Adapter
  defdelegate new_item(assigns, live_resource), to: Memory

  @impl Backpex.Adapter
  defdelegate change(item, attrs, fields, assigns, live_resource, opts), to: Memory

  @impl Backpex.Adapter
  defdelegate put_assoc(changeset, name, value, live_resource), to: Memory

  @impl Backpex.Adapter
  defdelegate insert(changeset, live_resource), to: Memory

  @impl Backpex.Adapter
  defdelegate update(changeset, live_resource), to: Memory

  @impl Backpex.Adapter
  defdelegate update_all(items, changes, live_resource), to: Memory

  @impl Backpex.Adapter
  defdelegate delete_all(items, live_resource), to: Memory
end
