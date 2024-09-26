defmodule Backpex.Adapters.Ecto do
  @config_schema [
    repo: [
      doc: "The `Ecto.Repo` that will be used to perform CRUD operations for the given schema.",
      type: :atom,
      required: true
    ],
    schema: [
      doc: "The `Ecto.Schema` for the resource.",
      type: :atom,
      required: true
    ],
    update_changeset: [
      doc: """
      Changeset to use when updating items. Additional metadata is passed as a keyword list via the third parameter:
      - `:assigns` - the assigns
      - `:target` - the name of the `form` target that triggered the changeset call. Default to `nil` if the call was not triggered by a form field.
      """,
      type: {:fun, 3},
      required: true
    ],
    create_changeset: [
      doc: """
      Changeset to use when creating items. Additional metadata is passed as a keyword list via the third parameter:
      - `:assigns` - the assigns
      - `:target` - the name of the `form` target that triggered the changeset call. Default to `nil` if the call was not triggered by a form field.
      """,
      type: {:fun, 3},
      required: true
    ]
  ]

  @moduledoc """
  The `Backpex.Adapter` to connect your `Backpex.LiveResource` to an `Ecto.Schema`.

  ## `adapter_config`

  #{NimbleOptions.docs(@config_schema)}
  """

  use Backpex.Adapter, config_schema: @config_schema
  import Ecto.Query

  @doc """
  Deletes multiple items.
  """
  @impl Backpex.Adapter
  def delete_all(items, config) do
    id_field = Backpex.Ecto.EctoUtils.get_primary_key_field(config[:schema])

    config[:schema]
    |> where([i], field(i, ^id_field) in ^Enum.map(items, &Map.get(&1, id_field)))
    |> config[:repo].delete_all()
  end
end
