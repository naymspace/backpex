defmodule Backpex.Test.MemoryNote do
  @moduledoc "A note that `Backpex.Adapters.Memory` keeps in the store `Backpex.Test.MemoryNotes`."
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: false}
  embedded_schema do
    field :title, :string
    field :likes, :integer
  end

  def changeset(note, attrs, _metadata), do: note |> cast(attrs, [:title, :likes]) |> validate_required([:title])
end

defmodule Backpex.Test.MemoryNoteLive do
  @moduledoc """
  Notes in memory, with `Backpex.Adapters.Memory`. The adapter runs no part of a query, so Backpex filters, searches,
  sorts, paginates and aggregates the notes itself.
  """
  use Backpex.LiveResource,
    adapter: Backpex.Adapters.Memory,
    adapter_config: [
      schema: Backpex.Test.MemoryNote,
      store: Backpex.Test.MemoryNotes,
      create_changeset: &Backpex.Test.MemoryNote.changeset/3,
      update_changeset: &Backpex.Test.MemoryNote.changeset/3
    ],
    init_order: %{by: :title, direction: :asc}

  import Backpex.Expr

  @impl Backpex.LiveResource
  def layout(_assigns), do: {Backpex.Test.Layouts, :admin}

  @impl Backpex.LiveResource
  def singular_name, do: "Note"

  @impl Backpex.LiveResource
  def plural_name, do: "Notes"

  @impl Backpex.LiveResource
  def scope(_assigns), do: expr(not starts_with(title, "Secret"))

  @impl Backpex.LiveResource
  def fields do
    [
      title: %{module: Backpex.Fields.Text, label: "Title", searchable: true},
      likes: %{module: Backpex.Fields.Number, label: "Likes"}
    ]
  end

  @impl Backpex.LiveResource
  def metrics do
    [
      total_likes: %{
        module: Backpex.Metrics.Value,
        label: "Total likes",
        aggregate: {:sum, :likes},
        format: &"#{&1} likes"
      }
    ]
  end
end
