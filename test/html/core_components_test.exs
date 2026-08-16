defmodule Backpex.HTML.CoreComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  import Backpex.HTML.CoreComponents

  # A thin wrapper so we can exercise the `dropdown/1` slots via render_component/2.
  defmodule TestComponent do
    use Phoenix.Component

    import Backpex.HTML.CoreComponents

    attr :readonly, :boolean, default: false
    attr :class, :any, default: nil

    def test_dropdown(assigns) do
      ~H"""
      <.dropdown id="test-dd" class={@class} readonly={@readonly}>
        <:trigger aria_label="open" class="trigger-class">Trigger</:trigger>
        <:menu>Menu content</:menu>
      </.dropdown>
      """
    end
  end

  describe "dropdown/1" do
    test "renders dropdown class and trigger role in non-readonly mode" do
      html = render_component(&TestComponent.test_dropdown/1, readonly: false, class: "w-full")

      doc = LazyHTML.from_fragment(html)
      outer = LazyHTML.query(doc, "#test-dd")
      trigger = LazyHTML.query(doc, "#test-dd-trigger")
      menu = LazyHTML.query(doc, "#test-dd-menu")

      assert LazyHTML.attribute(outer, "class") == ["dropdown w-full"]

      assert LazyHTML.attribute(trigger, "role") == ["button"]
      assert LazyHTML.attribute(trigger, "tabindex") == ["0"]
      assert LazyHTML.attribute(trigger, "aria-haspopup") == ["true"]
      assert LazyHTML.attribute(trigger, "aria-label") == ["open"]

      # menu div is present
      assert Enum.count(menu) == 1
    end

    test "renders inert div without interactive attrs in readonly mode" do
      html = render_component(&TestComponent.test_dropdown/1, readonly: true, class: "w-full")

      doc = LazyHTML.from_fragment(html)
      outer = LazyHTML.query(doc, "#test-dd")
      trigger = LazyHTML.query(doc, "#test-dd-trigger")
      menu = LazyHTML.query(doc, "#test-dd-menu")

      # User-supplied class is still passed through, but the dropdown class is not.
      [outer_class] = LazyHTML.attribute(outer, "class")
      refute outer_class =~ "dropdown"
      assert outer_class =~ "w-full"

      # No interactive attributes on the trigger in readonly mode.
      assert LazyHTML.attribute(trigger, "role") == []
      assert LazyHTML.attribute(trigger, "tabindex") == []
      assert LazyHTML.attribute(trigger, "aria-haspopup") == []
      assert LazyHTML.attribute(trigger, "aria-label") == []
      assert LazyHTML.attribute(trigger, "aria-labelledby") == []

      # Menu div is not rendered in readonly mode.
      assert Enum.empty?(menu)
    end

    test "passes through the user-supplied class on the outer wrapper in both modes" do
      for readonly <- [false, true] do
        html = render_component(&TestComponent.test_dropdown/1, readonly: readonly, class: "w-full")

        doc = LazyHTML.from_fragment(html)
        outer = LazyHTML.query(doc, "#test-dd")
        [outer_class] = LazyHTML.attribute(outer, "class")

        assert outer_class =~ "w-full",
               "expected w-full in outer class for readonly=#{readonly}, got #{inspect(outer_class)}"
      end
    end
  end
end
