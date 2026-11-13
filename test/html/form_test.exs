defmodule Backpex.HTML.FormTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias Backpex.HTML.Form, as: BackpexForm

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

  defmodule FormLive do
    @moduledoc false
    def config(:primary_key), do: :id
  end

  describe "index_form/1" do
    test "sends the inline edit to the LiveView without recovering it after a reconnect" do
      html =
        render_component(&BackpexForm.index_form/1,
          form: to_form(%{"value" => "Title"}, as: :index_form),
          name: :title,
          item: %{id: 1},
          live_resource: FormLive,
          inner_block: []
        )

      assert html =~ ~s(id="index-form-title-1")
      assert html =~ ~s(phx-change="index-edit")
      assert html =~ ~s(phx-auto-recover="ignore")
      assert html =~ ~s(<input type="hidden" name="index_edit[item]" value="1">)
    end
  end
end
