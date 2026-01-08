defmodule Backpex.PreferencesController do
  @moduledoc """
  Controller for persisting user preferences to the session.

  Accepts JSON requests and updates the session cookie.
  Used by the BackpexPreferences JS hook for async persistence.
  """

  use Phoenix.Controller, formats: [:json]

  import Plug.Conn
  alias Backpex.Preferences

  @doc """
  Updates one or more preferences.

  ## Single preference

      POST /backpex_preferences
      {"key": "global.theme", "value": "dark"}

  ## Batch update

      POST /backpex_preferences
      {"preferences": [
        {"key": "global.theme", "value": "dark"},
        {"key": "global.sidebar_open", "value": true}
      ]}
  """
  def update(conn, %{"key" => key, "value" => value}) do
    preferences = get_session(conn, Preferences.session_key()) || %{}
    updated = Preferences.put(preferences, key, value)

    conn
    |> put_session(Preferences.session_key(), updated)
    |> json(%{ok: true})
  end

  def update(conn, %{"preferences" => list}) when is_list(list) do
    preferences = get_session(conn, Preferences.session_key()) || %{}

    updated =
      Enum.reduce(list, preferences, fn
        %{"key" => key, "value" => value}, acc ->
          Preferences.put(acc, key, value)

        _invalid_item, acc ->
          acc
      end)

    conn
    |> put_session(Preferences.session_key(), updated)
    |> json(%{ok: true})
  end
end
