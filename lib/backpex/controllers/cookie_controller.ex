defmodule Backpex.CookieController do
  use Phoenix.Controller

  import Plug.Conn

  @form_url_key "_cookie_redirect_url"
  @form_resource_key "_resource"

  @backpex_key "backpex"
  @toggle_columns_key "column_toggle"
  @toggle_metrics_key "metric_visibility"

  def update(conn, %{"toggle_columns" => form_data}) do
    IO.inspect(form_data, label: :form_data_debug)

    resource = Map.get(form_data, @form_resource_key)

    to = redirect_url(form_data)
    fields = Map.drop(form_data, [@form_url_key, @form_resource_key])

    value = Map.put(%{}, resource, fields)

    conn
    |> put_backpex_session(@toggle_columns_key, value)
    |> redirect(to: to)
  end

  def update(conn, %{"toggle_metrics" => form_data}) do
    resource = Map.get(form_data, @form_resource_key)

    to = redirect_url(form_data)

    is_visible =
      conn
      |> get_session(@backpex_key)
      |> get_in([@toggle_metrics_key, resource])
      |> then(fn
        nil ->
          true

        value ->
          value
      end)

    value = Map.put(%{}, resource, !is_visible)

    conn
    |> put_backpex_session(@toggle_metrics_key, value)
    |> redirect(to: to)
  end

  defp redirect_path(%URI{path: path, query: nil}) do
    URI.new!(path)
  end

  defp redirect_path(%URI{path: path, query: query}) do
    URI.new!(path)
    |> Map.put(:query, query)
  end

  defp redirect_url(form_data) do
    form_data
    |> Map.get(@form_url_key)
    |> URI.parse()
    |> redirect_path()
    |> URI.to_string()
  end

  defp put_backpex_session(conn, key, value) do
    backpex_session = get_session(conn, @backpex_key) || %{}

    merged_value =
      backpex_session
      |> Map.get(key, %{})
      |> Map.merge(value)

    value = Map.put(backpex_session, key, merged_value)

    put_session(conn, @backpex_key, value)
  end
end
