defmodule BackpexWeb do
  @moduledoc """
  The entrypoint for defining the web interface of Backpex.

  ### Example

      use BackpexWeb, :html

  """

  @doc """
  Includes all globally available HTML functions and helpers.
  """
  def html do
    quote do
      use Phoenix.Component
      unquote(html_helpers())
    end
  end

  @doc """
  Includes all globally available field functions and helpers.
  """
  def field do
    quote do
      use Phoenix.Component
      use Phoenix.LiveComponent
      alias Backpex.HTML
      alias Backpex.HTML.Form, as: BackpexForm
      alias Backpex.HTML.Layout
      alias Backpex.LiveResource
      alias Phoenix.HTML.Form, as: PhoenixForm
      unquote(html_helpers())
    end
  end

  @doc """
  Includes all globally available item action functions and helpers.
  """
  def item_action do
    quote do
      use Phoenix.Component
      use Backpex.ItemAction
      import Phoenix.LiveView
      alias Backpex.Router
      unquote(html_helpers())
    end
  end

  def filter do
    quote do
      use Phoenix.Component
      import Ecto.Query, warn: false
      unquote(html_helpers())
    end
  end

  def metric do
    quote do
      use Phoenix.Component
      import Ecto.Query
      @behaviour Backpex.Metric
    end
  end

  defp html_helpers do
    quote do
      import Phoenix.HTML
      alias Phoenix.LiveView.JS

      @doc false
      def ok(socket), do: {:ok, socket}

      @doc false
      def noreply(socket), do: {:noreply, socket}
    end
  end

  @doc """
  When used, dispatch to the appropriate function.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
