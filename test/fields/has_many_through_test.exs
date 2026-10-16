defmodule Backpex.Fields.HasManyThroughTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Backpex.Fields.HasManyThrough
  alias Ecto.Changeset

  defmodule Child do
    @moduledoc false
    use Ecto.Schema

    schema "children" do
      field :name, :string
    end
  end

  defmodule Pivot do
    @moduledoc false
    use Ecto.Schema

    schema "pivots" do
      field :note, :string
      belongs_to :parent, Backpex.Fields.HasManyThroughTest.Parent
      belongs_to :child, Backpex.Fields.HasManyThroughTest.Child
    end

    def changeset(pivot, attrs) do
      pivot
      |> Changeset.cast(attrs, [:child_id, :note])
      |> Changeset.validate_required([:child_id, :note])
    end
  end

  defmodule Parent do
    @moduledoc false
    use Ecto.Schema

    schema "parents" do
      has_many :pivots, Backpex.Fields.HasManyThroughTest.Pivot, on_replace: :delete
      has_many :children, through: [:pivots, :child]
    end
  end

  defmodule ChildrenRepo do
    @moduledoc false
    def all(_query) do
      [
        Ecto.put_meta(%Child{id: 1, name: "Zulu"}, state: :loaded),
        Ecto.put_meta(%Child{id: 2, name: "Alpha"}, state: :loaded),
        Ecto.put_meta(%Child{id: 3, name: "Mike"}, state: :loaded)
      ]
    end
  end

  defmodule UntranslatedLive do
    @moduledoc false
    def translate({msg, opts}) do
      Enum.reduce(opts, msg, fn {key, value}, msg -> String.replace(msg, "%{#{key}}", to_string(value)) end)
    end
  end

  defmodule ChildLive do
    @moduledoc false
    def config(:primary_key), do: :id
    def singular_name, do: "Child"
    def translate(msg), do: UntranslatedLive.translate(msg)
  end

  defmodule ParentLive do
    @moduledoc false
    def adapter_config(:schema), do: Parent
    def adapter_config(:repo), do: ChildrenRepo
    def translate(msg), do: UntranslatedLive.translate(msg)
  end

  describe "render_form/1" do
    test "marks the invalid relation when the rows are sorted" do
      # Zulu is attached first and valid, Alpha second and invalid; sorted by name, Alpha comes first.
      changeset = changeset(%Parent{}, [%{child_id: 1, note: "valid"}, %{child_id: 2, note: ""}])

      html = render_form(changeset, sort_by: [:name])

      assert rows(html) == [{"Alpha", true}, {"Zulu", false}]
      assert html =~ ~s(aria-label="Error in relation with index 1")
      refute html =~ ~s(aria-label="Error in relation with index 0")
    end

    test "marks the invalid relation when the rows are not sorted" do
      changeset = changeset(%Parent{}, [%{child_id: 1, note: "valid"}, %{child_id: 2, note: ""}])

      html = render_form(changeset)

      assert rows(html) == [{"Zulu", false}, {"Alpha", true}]
      assert html =~ ~s(aria-label="Error in relation with index 1")
    end

    test "marks the invalid relation after a relation was detached" do
      pivots = [
        loaded_pivot(%Pivot{id: 10, child_id: 3, note: "detached"}),
        loaded_pivot(%Pivot{id: 11, child_id: 1, note: "valid"}),
        loaded_pivot(%Pivot{id: 12, child_id: 2, note: "invalid"})
      ]

      [detached, valid, invalid] = pivots

      changeset =
        %Parent{id: 1, pivots: pivots}
        |> Ecto.put_meta(state: :loaded)
        |> Changeset.change()
        |> Changeset.put_assoc(:pivots, [
          %{Changeset.change(detached) | action: :delete},
          Pivot.changeset(valid, %{}),
          Pivot.changeset(invalid, %{note: ""})
        ])
        |> Map.put(:action, :validate)

      html = render_form(changeset)

      assert rows(html) == [{"Zulu", false}, {"Alpha", true}]
      assert html =~ ~s(aria-label="Error in relation with index 2")

      html = render_form(changeset, sort_by: [:name])

      assert rows(html) == [{"Alpha", true}, {"Zulu", false}]
      assert html =~ ~s(aria-label="Error in relation with index 2")
    end
  end

  defp changeset(parent, pivot_params) do
    parent
    |> Changeset.cast(%{pivots: pivot_params}, [])
    |> Changeset.cast_assoc(:pivots, with: &Pivot.changeset/2)
    |> Map.put(:action, :validate)
  end

  defp loaded_pivot(pivot), do: Ecto.put_meta(pivot, state: :loaded)

  defp render_form(changeset, field_options \\ []) do
    field_options =
      Map.merge(
        %{
          module: HasManyThrough,
          label: "Children",
          display_field: :name,
          live_resource: ChildLive,
          child_fields: [name: %{module: Backpex.Fields.Text, label: "Name"}],
          pivot_fields: [note: %{module: Backpex.Fields.Text, label: "Note"}]
        },
        Map.new(field_options)
      )

    render_component(HasManyThrough,
      id: "has-many-through",
      name: :children,
      field: {:children, field_options},
      field_options: field_options,
      form: Phoenix.Component.to_form(changeset),
      changeset: changeset,
      live_resource: ParentLive,
      live_action: :edit,
      hide_label: false,
      readonly: false,
      type: :form
    )
  end

  # Returns the child name of each table row and whether the row shows the error icon.
  defp rows(html) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("tbody tr")
    |> Enum.map(fn row ->
      name = row |> LazyHTML.query("td:first-child") |> LazyHTML.text() |> String.trim()
      error? = row |> LazyHTML.query(~s([aria-label^="Error in relation"])) |> Enum.count() > 0

      {name, error?}
    end)
  end
end
