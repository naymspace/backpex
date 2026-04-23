defmodule Backpex.HTML.FormTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias Backpex.HTML.Form, as: BackpexForm

  # Build a bare `Phoenix.HTML.FormField` with the minimum needed for multi_select/1:
  # `field.id` (for the dropdown wrapper id), `field.name` (for the search/hidden inputs)
  # and `field.errors`.
  defp build_field do
    form = to_form(%{"tags" => ""}, as: nil)

    %Phoenix.HTML.FormField{
      id: "tags",
      name: "tags",
      errors: [],
      field: :tags,
      form: form,
      value: ""
    }
  end

  defp base_assigns(overrides) do
    defaults = [
      prompt: "Select an option",
      not_found_text: "No options found",
      options: [],
      search_input: "",
      event_target: nil,
      field_options: %{},
      field: build_field(),
      selected: [],
      show_select_all: true,
      show_more: false
    ]

    Keyword.merge(defaults, overrides)
  end

  describe "multi_select/1" do
    test "readonly prompt uses /60 contrast class" do
      assigns = base_assigns(readonly: true, selected: [])

      html = render_component(&BackpexForm.multi_select/1, assigns)

      doc = LazyHTML.from_fragment(html)
      # The prompt is the <p> rendered when `@selected == []`.
      prompt = LazyHTML.query(doc, "p")
      [prompt_class] = LazyHTML.attribute(prompt, "class")

      assert prompt_class =~ "text-base-content/60"
    end

    test "readonly badge has no remove button or badge-primary class" do
      assigns = base_assigns(readonly: true, selected: [{"Elixir", "elixir"}])

      html = render_component(&BackpexForm.multi_select/1, assigns)

      doc = LazyHTML.from_fragment(html)
      # In readonly mode the badge is a <span class="badge badge-sm badge-soft">.
      badge = LazyHTML.query(doc, "span.badge")
      [badge_class] = LazyHTML.attribute(badge, "class")

      assert badge_class =~ "badge"
      refute badge_class =~ "badge-primary"

      # No interactive remove control inside the badge.
      refute html =~ ~s(phx-click="toggle-option")
      # And no buttons rendered as part of the badge markup. (The dropdown itself does
      # not render a menu in readonly mode, so there should be no phx-click remove.)
      remove_buttons = LazyHTML.query(doc, "span.badge [phx-click]")
      assert Enum.empty?(remove_buttons)
    end

    test "non-readonly badge includes badge-primary and remove affordance" do
      assigns = base_assigns(readonly: false, selected: [{"Elixir", "elixir"}])

      html = render_component(&BackpexForm.multi_select/1, assigns)

      doc = LazyHTML.from_fragment(html)
      # In non-readonly mode the badge is a <div class="badge ... badge-primary ...">.
      badge = LazyHTML.query(doc, "div.badge")
      [badge_class] = LazyHTML.attribute(badge, "class")

      assert badge_class =~ "badge-primary"

      # The remove affordance is a div with role="button" and phx-click="toggle-option"
      # inside the badge.
      assert html =~ ~s(phx-click="toggle-option")
      remove = LazyHTML.query(doc, ~s(div.badge [phx-click="toggle-option"]))
      refute Enum.empty?(remove)
    end
  end
end
