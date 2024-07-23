defmodule Backpex.Filter do
  @moduledoc """
  The base behaviour for all filters. Injects also basic layout, form and delete button for a filters rendering.
  """

  @doc """
  Defines whether the filter can be used or not.
  """
  @callback can?(Phoenix.LiveView.Socket.assigns()) :: boolean()

  @doc """
  If no label is defined on the filter map, this value is used as the filter label.
  """
  @callback label :: String.t()

  @doc """
  The filter query that is executed if an option was selected.
  """
  @callback query(Ecto.Query.t(), any(), any()) :: Ecto.Query.t()

  @doc """
  Renders the filters selected value(s).
  """
  @callback render(Phoenix.LiveView.Socket.assigns()) :: Phoenix.LiveView.Rendered.t()

  @doc """
  Renders the filters options form.
  """
  @callback render_form(Phoenix.LiveView.Socket.assigns()) :: Phoenix.LiveView.Rendered.t()

  @optional_callbacks label: 0

  defmacro __using__(_opts) do
    quote do
      @behaviour Backpex.Filter

      @impl Backpex.Filter
      def can?(_assigns), do: true

      defoverridable can?: 1
    end
  end
end
