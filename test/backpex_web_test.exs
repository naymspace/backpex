defmodule BackpexWebTest.Support do
  @moduledoc false

  # Mimics a typical `MyAppWeb, :html` entrypoint that brings in `Phoenix.Component`.
  defmodule MyAppWeb do
    def html do
      quote do
        use Phoenix.Component
      end
    end

    defmacro __using__(which), do: apply(__MODULE__, which, [])
  end

  defmodule TestRepo do
    use Ecto.Repo, otp_app: :backpex, adapter: Ecto.Adapters.Postgres
  end

  defmodule TestSchema do
    use Ecto.Schema

    schema "items" do
      field :name, :string
    end
  end

  # Wrapped in macros (instead of direct `use`) so the formatter does not reorder them and
  # the tests can exercise both `use` orderings deterministically.
  @doc "Brings in `Phoenix.Component` the way an app-level `use MyAppWeb, :html` would."
  defmacro app_html do
    quote do
      use BackpexWebTest.Support.MyAppWeb, :html
    end
  end

  @doc "Defines a minimal `Backpex.LiveResource` with a `~H`-based render function."
  defmacro live_resource do
    quote do
      use Backpex.LiveResource,
        adapter: Backpex.Adapters.Ecto,
        adapter_config: [schema: BackpexWebTest.Support.TestSchema, repo: BackpexWebTest.Support.TestRepo]

      @impl Backpex.LiveResource
      def layout(_assigns), do: {Layouts, :admin}

      @impl Backpex.LiveResource
      def singular_name, do: "Item"

      @impl Backpex.LiveResource
      def plural_name, do: "Items"

      @impl Backpex.LiveResource
      def fields, do: []

      # A function component call would generate `__phoenix_component_verify__/1` –
      # the clause that was previously defined twice.
      def custom(var!(assigns)) do
        ~H"""
        <.link navigate="/">link</.link>
        """
      end
    end
  end

  @doc "Snapshots the accumulated `@before_compile` hooks. Must be the last statement in the module."
  defmacro snapshot do
    quote do
      @before_compile_hooks Module.get_attribute(__MODULE__, :before_compile) || []
      def __before_compile_hooks__, do: @before_compile_hooks
    end
  end
end

defmodule BackpexWebTest do
  use ExUnit.Case, async: true

  alias Phoenix.Component.Declarative

  require BackpexWebTest.Support, as: Support

  # `use MyAppWeb, :html` before `use Backpex.LiveResource` (conventional order).
  defmodule HtmlFirstLive do
    require Support

    Support.app_html()
    Support.live_resource()
    Support.snapshot()
  end

  # `use Backpex.LiveResource` before `use MyAppWeb, :html` (reverse order).
  defmodule LiveResourceFirstLive do
    require Support

    Support.live_resource()
    Support.app_html()
    Support.snapshot()
  end

  # `use Backpex.LiveResource` alone, without an app `:html` entrypoint.
  defmodule StandaloneLive do
    require Support

    Support.live_resource()
    Support.snapshot()
  end

  defp phoenix_component_hooks(module) do
    module.__before_compile_hooks__()
    |> Enum.filter(fn
      {Declarative, _fun} -> true
      Declarative -> true
      _hook -> false
    end)
  end

  describe "Backpex.LiveResource does not duplicate the Phoenix.Component before_compile hook" do
    test "when `use _, :html` comes first" do
      assert length(phoenix_component_hooks(HtmlFirstLive)) == 1
      assert function_exported?(HtmlFirstLive, :__phoenix_component_verify__, 1)
    end

    test "when `use _, :html` comes after (order-independent)" do
      assert length(phoenix_component_hooks(LiveResourceFirstLive)) == 1
      assert function_exported?(LiveResourceFirstLive, :__phoenix_component_verify__, 1)
    end

    test "and Backpex alone does not register the hook (import is enough for ~H)" do
      assert phoenix_component_hooks(StandaloneLive) == []
    end
  end

  test "the ~H sigil works in a LiveResource regardless of an app `:html` entrypoint" do
    for module <- [HtmlFirstLive, LiveResourceFirstLive, StandaloneLive] do
      html =
        %{}
        |> module.custom()
        |> Phoenix.LiveViewTest.rendered_to_string()

      assert html =~ "link"
    end
  end
end
