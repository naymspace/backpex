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

  Single-write `:unidentified` is treated as a no-op rather than an error:
  the response is `200 {ok: false, error: %{reason: "unidentified"}}` and no
  warning is logged. The JS hook fires writes from anonymous visitors
  whenever the session lapses — this avoids surfacing them as 4xx noise.
  Batches always halt on any error (including `:unidentified`) and return
  422.
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

      {:error, {key, :unidentified}} when length(entries) == 1 ->
        # Anonymous visitors hitting a non-session adapter is an expected
        # no-op, not a 4xx. The JS hook fires-and-forgets, so surfacing this
        # as an error would only pollute Logger without affecting clients.
        json(conn, %{ok: false, error: format_error({key, :unidentified})})

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
