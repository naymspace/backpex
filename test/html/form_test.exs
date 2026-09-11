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

  describe "Boolean inputs" do
    test "disabled checkboxes and toggles submit no values" do
      for type <- ["checkbox", "toggle"], checked <- [true, false] do
        html =
          render_component(&BackpexForm.input/1,
            type: type,
            name: "preferred",
            value: checked,
            disabled: true
          )

        assert submitted_params(html) == %{}
      end
    end

    test "editable checkboxes and toggles still submit checked and unchecked values" do
      for type <- ["checkbox", "toggle"], checked <- [true, false] do
        html =
          render_component(&BackpexForm.input/1,
            type: type,
            name: "preferred",
            value: checked
          )

        assert submitted_params(html) == %{"preferred" => to_string(checked)}
      end
    end

    test "an unrelated nested edit preserves a true readonly Boolean" do
      data = %{preferred: true, name: "Old supplier"}
      types = %{preferred: :boolean, name: :string}
      form = to_form(Ecto.Changeset.change({data, types}), as: "change[suppliers][0]")
      child_fields = [preferred: %{module: Backpex.Fields.Boolean, label: "Preferred", readonly: true}]
      fields = [suppliers: %{module: Backpex.Fields.InlineCRUD, child_fields: child_fields}]

      boolean_html =
        render_component(&Backpex.Fields.Boolean.render_form/1,
          form: form,
          name: :preferred,
          field_options: child_fields[:preferred],
          readonly: true,
          hide_label: true
        )

      name_html =
        render_component(&BackpexForm.input/1,
          type: "text",
          name: form[:name].name,
          value: "Updated supplier"
        )

      params = submitted_params(boolean_html <> name_html)
      change = Backpex.Field.drop_readonly_changes(params["change"], fields, %{})

      updated =
        {data, types}
        |> Ecto.Changeset.cast(change["suppliers"]["0"], [:preferred, :name])
        |> Ecto.Changeset.apply_changes()

      assert updated == %{preferred: true, name: "Updated supplier"}
    end
  end

  # Serialize successful controls in DOM order, including the hidden Boolean fallback.
  defp submitted_params(html) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(
      "input[name]:not([disabled]):not([type=checkbox]), input[name][type=checkbox][checked]:not([disabled])"
    )
    |> Enum.map(fn input ->
      [name] = LazyHTML.attribute(input, "name")
      [value] = LazyHTML.attribute(input, "value")
      {name, value}
    end)
    |> URI.encode_query()
    |> Plug.Conn.Query.decode()
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
