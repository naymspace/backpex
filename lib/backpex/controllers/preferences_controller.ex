defmodule Backpex.PreferencesController do
  @moduledoc """
  HTTP endpoint for persisting user preferences.

  Accepts JSON requests from the `BackpexPreferences` JS hook. Each call
  routes through `Backpex.Preferences`, which dispatches to the adapter
  configured for the key's prefix (see `Backpex.Preferences.Router`).

  ## Contracts

  Single write:

      POST /backpex_preferences
      {"key": "global.theme", "value": "dark"}

  Batch write:

      POST /backpex_preferences
      {"preferences": [
        {"key": "global.theme", "value": "dark"},
        {"key": "global.sidebar_open", "value": true}
      ]}

  The batch form is **best-effort, first-error-wins**: if any adapter refuses
  a write, the dispatcher halts at that entry, no further adapters are
  called, and the response is `422 {ok: false, error: %{key: _, reason: _}}`.
  Session-backed effects from earlier successful entries in the same batch
  are also dropped (the controller never applies them on the error path), so
  the session cookie is left unchanged. However, adapters that persist
  eagerly (e.g. a DB-backed adapter that wrote via `Repo.insert!`) may have
  already committed earlier writes — the adapter behaviour has no rollback
  primitive, so callers should treat partial success as possible.

  An adapter that refuses a write because its store cannot hold it returns
  `{:error, :too_large}`, which surfaces as
  `422 {ok: false, error: %{key: _, reason: "too_large"}}` — see the size limit
  section of `Backpex.Preferences.Adapters.Session`. The refusal is the
  designed outcome, not a bug: the alternative is a `CookieOverflowError` 500
  on this and every later request.

  Single-write `:unscoped` is treated as a no-op rather than an error:
  the response is `200 {ok: false, error: %{reason: "unscoped"}}` and no
  warning is logged. The JS hook fires writes from anonymous visitors
  whenever the session lapses — this avoids surfacing them as 4xx noise.
  Batches always halt on any error (including `:unscoped`) and return
  422.

  Entries in a batch are retained only when they are maps containing a binary
  `"key"` and a `"value"` field. Other members are silently discarded; an
  empty or all-invalid list is therefore a successful no-op (`200 {ok: true}`).
  A payload that matches neither the single nor batch shape returns
  `400 {ok: false, error: "missing key/value"}`.

  `Backpex.Preferences.put_batch/3` refuses a value that the built-in reader
  for its key cannot consume (`Backpex.Preferences.Keys.valid_value?/2`),
  returning `422 {ok: false, error: %{key: _, reason: "invalid_value"}}`. Keys
  Backpex does not own (`custom.*`, unknown `resource:` suffixes) have no known
  shape and pass through unchecked — an adapter that needs constraints on those
  enforces its own.

  That gate is a shape check, **not authorization**. This controller does not
  ask whether the caller may write the key, only whether the value would break
  a later render. Authorization belongs in the pipeline the route is mounted
  in, or in the adapter.
  """

  use Phoenix.Controller, formats: [:json]

  alias Backpex.Preferences
  alias Backpex.Preferences.Context

  require Logger

  @doc false
  def update(conn, %{"key" => key, "value" => value}) do
    update(conn, %{"preferences" => [%{"key" => key, "value" => value}]})
  end

  def update(conn, %{"preferences" => list}) when is_list(list) do
    entries =
      list
      |> Enum.filter(&match?(%{"key" => k, "value" => _value} when is_binary(k), &1))
      |> Enum.map(fn %{"key" => k, "value" => v} -> {k, v} end)

    ctx = Context.from_conn(conn)

    case Preferences.put_batch(ctx, entries) do
      {:ok, effects} ->
        conn
        |> Preferences.apply_effects_on_conn(effects)
        |> json(%{ok: true})

      {:error, {key, :unscoped}} when length(entries) == 1 ->
        # Anonymous visitors hitting a non-session adapter is an expected
        # no-op, not a 4xx. The JS hook fires-and-forgets, so surfacing this
        # as an error would only pollute Logger without affecting clients.
        json(conn, %{ok: false, error: format_error({key, :unscoped})})

      {:error, {key, reason}} ->
        Logger.warning(
          "[Backpex.PreferencesController] preference batch refused at key " <>
            inspect(key) <> ": " <> inspect(reason)
        )

        conn
        |> put_status(422)
        |> json(%{ok: false, error: format_error({key, reason})})
    end
  end

  def update(conn, _invalid_params) do
    conn
    |> put_status(400)
    |> json(%{ok: false, error: "missing key/value"})
  end

  defp format_error({key, reason}), do: %{key: key, reason: format_reason(reason)}
  defp format_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp format_reason(reason), do: inspect(reason)
end
