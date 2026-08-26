defmodule Backpex.Authorization do
  @moduledoc """
  Central entry point for all Backpex authorization checks.

  Every check ultimately calls `c:Backpex.LiveResource.can?/3` on the given LiveResource. Routing all
  checks through this module gives Backpex a single place to enforce authorization — and a single
  place to extend it later (for example with a dedicated authorizer behaviour).

  There are two flavours of functions:

  * **Preflight** (`can?/4`, `can_all?/4`) — answer a question. Use these in the UI to decide whether
    to render or disable a control.
  * **Gates** (`authorize!/4`, `authorize_all!/4`) — enforce the answer. Use these right before
    something actually happens. They raise instead of returning `false`.

  ## Failure semantics

  * unauthorized → `Backpex.ForbiddenError` (403)
  * `nil` item in `authorize_all!/4` (a stale or forged item id) → `Backpex.NoResultsError` (404)

  A `nil` item never reaches `c:Backpex.LiveResource.can?/3` through `authorize_all!/4`. This keeps
  user implementations free of `nil` clauses they never asked for, and it does not leak whether an
  id exists.

  ## Strict semantics

  `can_all?/4` and `authorize_all!/4` are strict: a single unauthorized item makes the whole call
  fail. Backpex does not silently drop unauthorized items from a selection.

  Note that `Enum.all?/2` returns `true` for an empty list, so an empty selection passes vacuously.
  Callers that need "empty means not allowed" (a disabled bulk action button, for example) must
  handle the empty case themselves.
  """

  @doc """
  Returns whether `action` may be performed on `item` for the given LiveResource.

  Pass `nil` as `item` for actions that are not bound to a specific item (`:index`, `:new`, resource
  actions).
  """
  @spec can?(module(), map(), atom(), map() | nil) :: boolean()
  def can?(live_resource, assigns, action, item) when is_atom(live_resource) and is_map(assigns) and is_atom(action) do
    live_resource.can?(assigns, action, item)
  end

  @doc """
  Returns whether `action` may be performed on **every** item in `items`.

  Returns `true` for an empty list.
  """
  @spec can_all?(module(), map(), atom(), list()) :: boolean()
  def can_all?(live_resource, assigns, action, items) when is_list(items) do
    Enum.all?(items, &can?(live_resource, assigns, action, &1))
  end

  @doc """
  Ensures `action` may be performed on `item`, raising `Backpex.ForbiddenError` otherwise.

  Returns `:ok`.
  """
  @spec authorize!(module(), map(), atom(), map() | nil) :: :ok
  def authorize!(live_resource, assigns, action, item) do
    if can?(live_resource, assigns, action, item) do
      :ok
    else
      raise Backpex.ForbiddenError
    end
  end

  @doc """
  Ensures `action` may be performed on **every** item in `items`.

  Raises `Backpex.ForbiddenError` when any item is not authorized and `Backpex.NoResultsError` when
  the list contains `nil` (a stale or forged item id).

  Returns `:ok`. An empty list passes.
  """
  @spec authorize_all!(module(), map(), atom(), list()) :: :ok
  def authorize_all!(live_resource, assigns, action, items) when is_list(items) do
    Enum.each(items, fn
      nil -> raise Backpex.NoResultsError
      item -> authorize!(live_resource, assigns, action, item)
    end)
  end
end
