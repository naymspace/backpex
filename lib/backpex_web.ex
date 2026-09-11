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
  Includes the functions and helpers available inside a `Backpex.LiveResource`.

  Unlike `html/0`, this only *imports* `Phoenix.Component` instead of `use`-ing it. A
  LiveResource only needs the `~H` sigil (for the injected `render_resource_slot/3` clauses
  and for user-defined render functions), and `import` is enough for that.

  If a LiveResource needs to declare its own function components with `attr`/`slot`, it should
  additionally `use MyAppWeb, :html` (or `use Phoenix.Component`).
  """
  # We deliberately `import` (rather than `use`) Phoenix.Component here. `use Phoenix.Component`
  # registers the Phoenix.Component.Declarative `@before_compile` hook, which Elixir does not
  # deduplicate. When the module also brings in Phoenix.Component (e.g. via `use MyAppWeb, :html`)
  # the hook would run twice and define `__phoenix_component_verify__/1` (and `__components__/0`)
  # twice; Elixir 1.20+ rejects the duplicate as a redundant clause, failing compilation under
  # `--warnings-as-errors`.
  #
  # Phoenix.Component.Declarative is required so the injected `~H` templates still compile when
  # the module additionally brings in the component-aware `def` (via `use MyAppWeb, :html`),
  # regardless of the order of the `use` statements.
  def live_resource do
    quote do
      import Phoenix.Component

      require Phoenix.Component.Declarative

      unquote(html_helpers())
    end
  end

  @doc """
  Includes all globally available field functions and helpers.
  """
  def field do
    quote do
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

      import Backpex.HTML.Form, only: [error: 1]
      import Ecto.Query, warn: false

      unquote(html_helpers())
    end
  end

  def metric do
    quote do
      @behaviour Backpex.Metric

      use Phoenix.Component

      import Ecto.Query
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
