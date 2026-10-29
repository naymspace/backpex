defmodule Backpex.Fields.InlineCRUDTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [to_form: 2]
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Backpex.Fields.InlineCRUD

  defmodule Link do
    @moduledoc false
    use Ecto.Schema

    embedded_schema do
      field :label, :string
      field :url, :string
    end
  end

  defmodule Supplier do
    @moduledoc false
    use Ecto.Schema

    schema "suppliers" do
      field :label, :string
      field :url, :string
      field :product_id, :integer
    end
  end

  defmodule Product do
    @moduledoc false
    use Ecto.Schema

    schema "products" do
      embeds_many :links, Link, on_replace: :delete
      has_many :suppliers, Supplier, on_replace: :delete
    end
  end

  # A LiveResource that returns Backpex's texts untranslated, with their bindings filled in.
  defmodule UntranslatedLive do
    @moduledoc false
    def translate({msg, opts}) do
      Enum.reduce(opts, msg, fn {key, value}, msg -> String.replace(msg, "%{#{key}}", to_string(value)) end)
    end
  end

  defp product do
    %Product{
      links: [%Link{id: "a", url: "https://a.example"}, %Link{id: "b", url: "https://b.example"}],
      suppliers: [%Supplier{id: 1, url: "https://a.example"}, %Supplier{id: 2, url: "https://b.example"}]
    }
  end

  defp render_form(name, overrides \\ []) do
    {product, overrides} = Keyword.pop_lazy(overrides, :product, &product/0)
    form = product |> Ecto.Changeset.change() |> to_form(as: :change)

    assigns =
      Keyword.merge(
        [
          form: form,
          name: name,
          field_options: %{label: "Rows"},
          child_fields: [],
          readonly: false,
          live_resource: UntranslatedLive,
          errors: []
        ],
        overrides
      )

    render_component(&InlineCRUD.render_form/1, assigns)
    |> LazyHTML.from_fragment()
  end

  for name <- [:links, :suppliers] do
    describe "render_form/1 for #{name}" do
      @name name

      test "renders a focusable, labelled delete button per row that drops the row" do
        buttons = @name |> render_form() |> LazyHTML.query("button[name='change[#{@name}_delete][]']")

        assert Enum.count(buttons) == 2
        assert LazyHTML.attribute(buttons, "type") == ["button", "button"]
        assert LazyHTML.attribute(buttons, "value") == ["0", "1"]
        assert LazyHTML.attribute(buttons, "aria-label") == ["Delete entry 1", "Delete entry 2"]
        assert LazyHTML.attribute(buttons, "tabindex") == []

        for click <- LazyHTML.attribute(buttons, "phx-click") do
          assert click =~ ~s(["dispatch",{"event":"change"}])
        end
      end

      test "moves focus to the add control only when the last row is deleted" do
        html = render_form(@name)

        [add_entry_id] =
          html |> LazyHTML.query("input[name='change[#{@name}_order][]'][type=checkbox]") |> LazyHTML.attribute("id")

        [first_click, last_click] =
          html |> LazyHTML.query("button[name='change[#{@name}_delete][]']") |> LazyHTML.attribute("phx-click")

        assert add_entry_id == "change_#{@name}_add_entry"
        refute first_click =~ "focus"
        assert last_click =~ ~s(["focus",{"to":"##{add_entry_id}"}])
      end

      test "does not render the delete control as a hidden checkbox" do
        assert render_form(@name)
               |> LazyHTML.query("input[type=checkbox][name='change[#{@name}_delete][]']")
               |> Enum.empty?()
      end

      test "renders one header row whose labels name the inputs of every row" do
        child_fields = [
          label: %{module: Backpex.Fields.Text, label: "Label"},
          url: %{module: Backpex.Fields.Text, label: "URL"}
        ]

        html = render_form(@name, child_fields: child_fields)

        header_ids =
          html |> LazyHTML.query("[id^='inline-crud-header-label-#{@name}-']") |> LazyHTML.attribute("id")

        assert header_ids == ["inline-crud-header-label-#{@name}-label", "inline-crud-header-label-#{@name}-url"]

        labelledby = html |> LazyHTML.query("input[aria-labelledby]") |> LazyHTML.attribute("aria-labelledby")

        assert length(labelledby) == 4

        for ids <- labelledby, id <- String.split(ids) do
          assert html |> LazyHTML.query("##{id}") |> Enum.count() == 1
        end
      end

      test "renders no header row without rows" do
        child_fields = [label: %{module: Backpex.Fields.Text, label: "Label"}]
        product = %Product{links: [], suppliers: []}

        assert render_form(@name, child_fields: child_fields, product: product)
               |> LazyHTML.query("[id^='inline-crud-header-label-']")
               |> Enum.empty?()
      end

      test "renders no delete buttons when readonly" do
        assert render_form(@name, readonly: true)
               |> LazyHTML.query("button[name='change[#{@name}_delete][]']")
               |> Enum.empty?()
      end
    end
  end

  describe "class of a child field" do
    test "is added to the header and every cell of the child field's column only" do
      child_fields = [
        label: %{module: Backpex.Fields.Text, label: "Label", class: "w-1/3"},
        url: %{module: Backpex.Fields.Text, label: "URL"}
      ]

      html = render_form(:links, child_fields: child_fields)

      assert column_classes(html, "w-1\\/3") == {["inline-crud-header-label-links-label"], ["label", "label"]}
    end

    test "can be the result of a function" do
      child_fields = [
        label: %{module: Backpex.Fields.Text, label: "Label"},
        url: %{module: Backpex.Fields.Text, label: "URL", class: fn %{readonly: false} -> "w-2/3" end}
      ]

      html = render_form(:links, child_fields: child_fields)

      assert column_classes(html, "w-2\\/3") == {["inline-crud-header-label-links-url"], ["url", "url"]}
    end
  end

  # Returns the ids of the header cells and the child field names of the inputs in the row cells with the class.
  defp column_classes(html, class) do
    header_ids = html |> LazyHTML.query("div.table-cell.#{class}[id]") |> LazyHTML.attribute("id")

    input_fields =
      html
      |> LazyHTML.query("div.table-row > div.table-cell.#{class} input[type=text]")
      |> LazyHTML.attribute("name")
      |> Enum.map(&(Regex.run(~r/\[(\w+)\]$/, &1, capture: :all_but_first) |> hd()))

    {header_ids, input_fields}
  end
end
