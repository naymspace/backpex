defmodule Backpex.Test.RecordingAdapter do
  @moduledoc """
  A data layer adapter that delegates every call to `Backpex.Adapters.Ecto` and reports it with the telemetry event
  `[:backpex, :test, :adapter, :call]`, so tests can prove that a LiveResource uses the adapter of its `adapter` option.

  The metadata holds the `:function`, the `:live_resource` and the `:pid` and `:callers` of the
  calling process, so an async test only handles the calls of its own LiveViews.
  """
  @behaviour Backpex.Adapter

  alias Backpex.Adapters.Ecto, as: EctoAdapter

  @event [:backpex, :test, :adapter, :call]

  @doc "The telemetry event emitted for every call."
  def event, do: @event

  def validate_config!(config), do: EctoAdapter.validate_config!(config)

  @impl Backpex.Adapter
  def get(primary_value, fields, assigns, live_resource),
    do: record(:get, live_resource, [primary_value, fields, assigns, live_resource])

  @impl Backpex.Adapter
  def list(criteria, fields, assigns, live_resource),
    do: record(:list, live_resource, [criteria, fields, assigns, live_resource])

  @impl Backpex.Adapter
  def count(criteria, fields, assigns, live_resource),
    do: record(:count, live_resource, [criteria, fields, assigns, live_resource])

  @impl Backpex.Adapter
  def metric(metric, criteria, fields, assigns, live_resource),
    do: record(:metric, live_resource, [metric, criteria, fields, assigns, live_resource])

  @impl Backpex.Adapter
  def new_item(assigns, live_resource), do: record(:new_item, live_resource, [assigns, live_resource])

  @impl Backpex.Adapter
  def association(name, live_resource), do: record(:association, live_resource, [name, live_resource])

  @impl Backpex.Adapter
  def list_options(field, criteria, assigns, live_resource),
    do: record(:list_options, live_resource, [field, criteria, assigns, live_resource])

  @impl Backpex.Adapter
  def list_options_by_key(field, criteria, assigns_by_key, live_resource),
    do: record(:list_options_by_key, live_resource, [field, criteria, assigns_by_key, live_resource])

  @impl Backpex.Adapter
  def count_options(field, criteria, assigns, live_resource),
    do: record(:count_options, live_resource, [field, criteria, assigns, live_resource])

  @impl Backpex.Adapter
  def options_key(field, assigns, live_resource),
    do: record(:options_key, live_resource, [field, assigns, live_resource])

  @impl Backpex.Adapter
  def field_type(name, live_resource), do: record(:field_type, live_resource, [name, live_resource])

  @impl Backpex.Adapter
  def insert(item, live_resource), do: record(:insert, live_resource, [item, live_resource])

  @impl Backpex.Adapter
  def update(item, live_resource), do: record(:update, live_resource, [item, live_resource])

  @impl Backpex.Adapter
  def update_all(items, updates, live_resource), do: record(:update_all, live_resource, [items, updates, live_resource])

  @impl Backpex.Adapter
  def change(item, attrs, fields, assigns, live_resource, opts),
    do: record(:change, live_resource, [item, attrs, fields, assigns, live_resource, opts])

  @impl Backpex.Adapter
  def put_assoc(changeset, name, value, live_resource),
    do: record(:put_assoc, live_resource, [changeset, name, value, live_resource])

  @impl Backpex.Adapter
  def delete_all(items, live_resource), do: record(:delete_all, live_resource, [items, live_resource])

  defp record(function, live_resource, args) do
    :telemetry.execute(@event, %{}, %{
      function: function,
      live_resource: live_resource,
      pid: self(),
      callers: Process.get(:"$callers", [])
    })

    apply(EctoAdapter, function, args)
  end
end
