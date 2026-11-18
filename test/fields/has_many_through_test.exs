defmodule Backpex.Fields.HasManyThroughTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Backpex.Fields.HasManyThrough
  alias Ecto.Changeset
  alias Phoenix.LiveView.Socket

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

  # A child whose key is `isbn`, while its pivot has an `id`.
  defmodule Book do
    @moduledoc false
    use Ecto.Schema

    @primary_key {:isbn, :string, autogenerate: false}
    schema "books" do
      field :title, :string
    end
  end

  defmodule Shelving do
    @moduledoc false
    use Ecto.Schema

    schema "shelvings" do
      field :shelf, :string
      belongs_to :library, Backpex.Fields.HasManyThroughTest.Library
      belongs_to :book, Book, foreign_key: :book_isbn, references: :isbn, type: :string
    end
  end

  defmodule Library do
    @moduledoc false
    use Ecto.Schema

    schema "libraries" do
      has_many :shelvings, Shelving, on_replace: :delete
      has_many :books, through: [:shelvings, :book]
    end
  end

  defmodule BooksRepo do
    @moduledoc false
    def all(_query) do
      [
        Ecto.put_meta(%Book{isbn: "isbn-1", title: "Dune"}, state: :loaded),
        Ecto.put_meta(%Book{isbn: "isbn-2", title: "Emma"}, state: :loaded)
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
    def config(:adapter), do: Backpex.Adapters.Ecto
    def adapter_config(:schema), do: Parent
    def adapter_config(:repo), do: ChildrenRepo
    def translate(msg), do: UntranslatedLive.translate(msg)
  end

  defmodule BookLive do
    @moduledoc false
    def config(:primary_key), do: :isbn
    def singular_name, do: "Book"
    def translate(msg), do: UntranslatedLive.translate(msg)
  end

  defmodule LibraryLive do
    @moduledoc false
    def config(:adapter), do: Backpex.Adapters.Ecto
    def adapter_config(:schema), do: Library
    def adapter_config(:repo), do: BooksRepo
    def translate(msg), do: UntranslatedLive.translate(msg)
  end

  describe "param_keys/2" do
    test "returns the pivot association with the keys of the inputs of an entry" do
      field = {:children, %{pivot_fields: [note: %{module: Backpex.Fields.Text, label: "Note"}]}}

      assert HasManyThrough.param_keys(field, %{live_resource: ParentLive}) == [{"pivots", ["child_id", "id", "note"]}]

      assert HasManyThrough.param_keys({:children, %{}}, %{live_resource: ParentLive}) == [
               {"pivots", ["child_id", "id"]}
             ]
    end

    test "lets no other column of the pivot through the form" do
      fields = [children: %{module: HasManyThrough, pivot_fields: [note: %{module: Backpex.Fields.Text}]}]
      entry = %{"id" => "1", "child_id" => "2", "note" => "Blue", "parent_id" => "9"}

      assert Backpex.Field.editable_changes(%{"pivots" => %{"0" => entry}}, fields, %{live_resource: ParentLive}) ==
               %{"pivots" => %{"0" => Map.delete(entry, "parent_id")}}
    end
  end

  describe "handle_event/3" do
    test "ignores the buttons of a readonly field" do
      socket = %Socket{assigns: %{__changed__: %{}, readonly: true}}

      for {event, params} <- [{"new-relational", %{}}, {"detach-relational", %{"index" => "0"}}] do
        assert HasManyThrough.handle_event(event, params, socket) == {:noreply, socket}
      end

      refute_received {:put_assoc, _assoc}
    end
  end

  # The invalid pivot gets no `note` param, so its input counts as unused and shows no error text. Rendering an error
  # text would print a warning about the missing `:error_translator_function` configuration.
  describe "render_form/1" do
    test "marks the invalid relation when the rows are sorted" do
      # Zulu is attached first and valid, Alpha second and invalid; sorted by name, Alpha comes first.
      changeset = changeset(%Parent{}, [%{child_id: 1, note: "valid"}, %{child_id: 2}])

      html = render_form(changeset, sort_by: [:name])

      assert rows(html) == [{"Alpha", true}, {"Zulu", false}]
      assert html =~ ~s(aria-label="Error in relation with index 1")
      refute html =~ ~s(aria-label="Error in relation with index 0")
    end

    test "marks the invalid relation when the rows are not sorted" do
      changeset = changeset(%Parent{}, [%{child_id: 1, note: "valid"}, %{child_id: 2}])

      html = render_form(changeset)

      assert rows(html) == [{"Zulu", false}, {"Alpha", true}]
      assert html =~ ~s(aria-label="Error in relation with index 1")
    end

    test "marks the invalid relation after a relation was detached" do
      pivots = [
        loaded_pivot(%Pivot{id: 10, child_id: 3, note: "detached"}),
        loaded_pivot(%Pivot{id: 11, child_id: 1, note: "valid"}),
        loaded_pivot(%Pivot{id: 12, child_id: 2, note: nil})
      ]

      [detached, valid, invalid] = pivots

      changeset =
        %Parent{id: 1, pivots: pivots}
        |> Ecto.put_meta(state: :loaded)
        |> Changeset.change()
        |> Changeset.put_assoc(:pivots, [
          %{Changeset.change(detached) | action: :delete},
          Pivot.changeset(valid, %{}),
          Pivot.changeset(invalid, %{})
        ])
        |> Map.put(:action, :validate)

      html = render_form(changeset)

      assert rows(html) == [{"Zulu", false}, {"Alpha", true}]
      assert html =~ ~s(aria-label="Error in relation with index 2")

      html = render_form(changeset, sort_by: [:name])

      assert rows(html) == [{"Alpha", true}, {"Zulu", false}]
      assert html =~ ~s(aria-label="Error in relation with index 2")
    end

    test "marks no relation before the form was validated" do
      changeset =
        %Parent{}
        |> changeset([%{child_id: 1, note: "valid"}, %{child_id: 2}])
        |> Map.put(:action, nil)

      html = render_form(changeset, sort_by: [:name])

      assert rows(html) == [{"Alpha", false}, {"Zulu", false}]
    end
  end

  describe "a child whose key differs from the key of the pivot" do
    setup do
      shelvings = [
        loaded_pivot(%Shelving{id: 10, book_isbn: "isbn-1", shelf: "A"}),
        loaded_pivot(%Shelving{id: 11, book_isbn: "isbn-2", shelf: "B"})
      ]

      %{library: Ecto.put_meta(%Library{id: 1, shelvings: shelvings}, state: :loaded)}
    end

    test "render_form/1 renders the keys of the children as option values", %{library: library} do
      html = library |> Changeset.change() |> render_books_form()

      assert rows(html) == [{"Dune", false}, {"Emma", false}]

      for index <- 0..1 do
        options = html |> LazyHTML.from_fragment() |> LazyHTML.query("#edit-relational-modal-#{index} select option")

        assert LazyHTML.attribute(options, "value") == ["", "isbn-1", "isbn-2"]
      end
    end

    test "render_form/1 keeps the other relations after a saved relation was detached", %{library: library} do
      [detached, kept] = library.shelvings

      changeset =
        library
        |> Changeset.change()
        |> Changeset.put_assoc(:shelvings, [%{Changeset.change(detached) | action: :delete}, Changeset.change(kept)])

      assert changeset |> render_books_form() |> rows() == [{"Emma", false}]
    end

    test "detaching marks a saved relation for deletion and removes an unsaved one", %{library: library} do
      [saved, other_saved] = library.shelvings
      changeset = library |> Changeset.change() |> Changeset.put_assoc(:shelvings, [saved, other_saved, %{}])
      {:ok, socket} = changeset |> books_assigns() |> HasManyThrough.update(%Socket{})

      HasManyThrough.handle_event("detach-relational", %{"index" => "0"}, socket)
      assert_received {:put_assoc, {:shelvings, [%{action: :delete, data: %{id: 10}}, %{data: %{id: 11}}, _new]}}

      HasManyThrough.handle_event("detach-relational", %{"index" => "2"}, socket)
      assert_received {:put_assoc, {:shelvings, [%{data: %{id: 10}}, %{data: %{id: 11}}]}}
    end
  end

  defp books_assigns(changeset) do
    field_options = %{
      module: HasManyThrough,
      label: "Books",
      display_field: :title,
      live_resource: BookLive,
      child_fields: [title: %{module: Backpex.Fields.Text, label: "Title"}],
      pivot_fields: [shelf: %{module: Backpex.Fields.Text, label: "Shelf"}]
    }

    %{
      id: "has-many-through",
      name: :books,
      field: {:books, field_options},
      field_options: field_options,
      form: Phoenix.Component.to_form(changeset),
      changeset: changeset,
      live_resource: LibraryLive,
      live_action: :edit,
      hide_label: false,
      readonly: false,
      type: :form
    }
  end

  defp render_books_form(changeset), do: render_component(HasManyThrough, books_assigns(changeset))

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

  describe "detach-relational" do
    setup do
      pivot = Ecto.put_meta(%Pivot{id: 10, child_id: 1, note: "a"}, state: :loaded)
      changeset = Changeset.change(%Parent{id: 1, pivots: [pivot]})

      socket = %Socket{
        assigns: %{
          __changed__: %{},
          changeset: changeset,
          association: %{pivot: %{field: :pivots, queryable: Pivot, primary_key: [:id]}},
          field_options: %{live_resource: ChildLive}
        }
      }

      %{socket: socket}
    end

    test "marks an existing relation for deletion", %{socket: socket} do
      assert {:noreply, _socket} = HasManyThrough.handle_event("detach-relational", %{"index" => "0"}, socket)

      assert_received {:put_assoc, {:pivots, [%Changeset{action: :delete}]}}
    end

    test "ignores an index that is not an integer or out of range", %{socket: socket} do
      for index <- ["abc", "0x", "", "5", "-3", 1, nil] do
        assert {:noreply, _socket} = HasManyThrough.handle_event("detach-relational", %{"index" => index}, socket)
      end

      refute_received {:put_assoc, _}
    end
  end
end
