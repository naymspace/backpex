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

  The batch form is **all-or-nothing**: if any adapter refuses a write, no
  side effects are applied, the response is `200 {ok: false, errors: [...]}`,
  and the session cookie is left unchanged. A partial-success state for
  preferences is more confusing than a clean failure.
  """

  use Phoenix.Controller, formats: [:json]

  alias Backpex.Preferences
  alias Backpex.Preferences.Context

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

      {:error, errors} ->
        conn
        |> put_status(200)
        |> json(%{ok: false, errors: Enum.map(errors, &format_error/1)})
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
