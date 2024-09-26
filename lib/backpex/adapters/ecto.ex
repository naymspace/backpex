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
    ],
    item_query: [
      doc: """
      The function that can be used to modify the ecto query. It will be used when resources are being fetched. This
      happens on `index`, `edit` and `show` view. In most cases this function will be used to filter items on `index`
      view based on certain criteria, but it may also be used to join other tables on `edit` or `show` view.

      This function should accept the following parameters:

      - `query` - `Ecto.Query.t()`
      - `live_action` - atom()`
      - `assigns` - `map()`

      It should return an `Ecto.Queryable`. It is recommended to build your `item_query` on top of the incoming query.
      Otherwise you will likely get binding errors.
      """,
      type: {:fun, 3}
    ]
  ]

  @moduledoc """
  The `Backpex.Adapter` to connect your `Backpex.LiveResource` to an `Ecto.Schema`.

  ## `adapter_config`

  #{NimbleOptions.docs(@config_schema)}
  """

  use Backpex.Adapter, config_schema: @config_schema
  alias Backpex.Ecto.EctoUtils
  import Ecto.Query

  @doc """
  Gets a database record with the given primary key value.

  Returns `nil` if no result was found.
  """
  @impl Backpex.Adapter
  def get(primary_key_value, fields, assigns, config) do
    item_query = prepare_item_query(config, assigns)

    record_query(primary_key_value, config[:schema], item_query, fields)
    |> config[:repo].one()
  end

  @doc """
  Gets a database record with the given primary key value.

  Raises `Ecto.NoResultsError` if no record was found.
  """
  @impl Backpex.Adapter
  def get!(primary_key_value, fields, assigns, config) do
    item_query = prepare_item_query(config, assigns)

    record_query(primary_key_value, config[:schema], item_query, fields)
    |> config[:repo].one!()
  end

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

  @doc """
  Gets name by schema. This is the last part of the module name as a lowercase atom.

  TODO: Make this private once all fields are using the adapter abstractions.
  """
  # sobelow_skip ["DOS.StringToAtom"]
  def name_by_schema(schema) do
    schema
    |> Module.split()
    |> List.last()
    |> String.downcase()
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    |> String.to_atom()
  end

  # --- PRIVATE

  defp prepare_item_query(config, assigns) do
    query_fun = config[:item_query] || fn query, _live_action, _assigns -> query end

    &query_fun.(&1, assigns.live_action, assigns)
  end

  defp record_query(id, schema, item_query, fields) do
    schema_name = name_by_schema(schema)

    id_field = EctoUtils.get_primary_key_field(schema)
    id_type = schema.__schema__(:type, id_field)
    associations = associations(fields, schema)

    from(item in schema, as: ^schema_name, distinct: field(item, ^id_field))
    |> item_query.()
    |> maybe_join(associations)
    |> maybe_preload(associations, fields)
    |> maybe_merge_dynamic_fields(fields)
    |> where_id(schema_name, id_field, id_type, id)
  end

  defp where_id(query, schema_name, id_field, :id, id) do
    case Ecto.Type.cast(:id, id) do
      {:ok, valid_id} -> where(query, [{^schema_name, schema_name}], field(schema_name, ^id_field) == ^valid_id)
      :error -> raise Ecto.NoResultsError, queryable: query
    end
  end

  defp where_id(query, schema_name, id_field, :binary_id, id) do
    case Ecto.UUID.cast(id) do
      {:ok, valid_id} -> where(query, [{^schema_name, schema_name}], field(schema_name, ^id_field) == ^valid_id)
      :error -> raise Ecto.NoResultsError, queryable: query
    end
  end

  defp where_id(query, schema_name, id_field, _id_type, id) do
    where(query, [{^schema_name, schema_name}], field(schema_name, ^id_field) == ^id)
  end

  defp associations(fields, schema) do
    fields
    |> Enum.filter(fn {_name, field_options} = field -> field_options.module.association?(field) end)
    |> Enum.map(fn
      {name, field_options} ->
        association = schema.__schema__(:association, name)

        if association == nil do
          name_str = name |> Atom.to_string()
          without_id = String.replace(name_str, ~r/_id$/, "")

          # credo:disable-for-lines:3 Credo.Check.Refactor.Nesting
          raise """
          The field "#{name}"" is not an association but used as if it were one with the field module #{inspect(field_options.module)}.
          #{if without_id != name_str,
            do: """
            You are using a field ending with _id. Please make sure to use the correct field name for the association. Try using the name of the association, maybe "#{without_id}"?
            """,
            else: ""}.
          """
        end

        case field_options do
          %{custom_alias: custom_alias} ->
            association |> Map.from_struct() |> Map.put(:custom_alias, custom_alias)

          _ ->
            association |> Map.from_struct()
        end
    end)
  end

  defp maybe_join(query, []), do: query

  defp maybe_join(query, associations) do
    Enum.reduce(associations, query, fn
      %{queryable: queryable, owner_key: owner_key, cardinality: :one} = association, query ->
        custom_alias = Map.get(association, :custom_alias, name_by_schema(queryable))

        if has_named_binding?(query, custom_alias) do
          query
        else
          from(item in query,
            left_join: b in ^queryable,
            as: ^custom_alias,
            on: field(item, ^owner_key) == field(b, ^EctoUtils.get_primary_key_field(queryable))
          )
        end

      _relation, query ->
        query
    end)
  end

  defp maybe_preload(query, [], _fields), do: query

  defp maybe_preload(query, associations, fields) do
    preload_items =
      Enum.map(associations, fn %{field: assoc_field} = association ->
        field = Enum.find(fields, fn {name, _field_options} -> name == assoc_field end)

        case field do
          {_name, %{display_field: display_field, select: select}} ->
            queryable = Map.get(association, :queryable)
            custom_alias = Map.get(association, :custom_alias, name_by_schema(queryable))

            preload_query =
              queryable
              |> from(as: ^custom_alias)
              |> select_merge(^%{display_field => select})

            {assoc_field, preload_query}

          _field ->
            assoc_field
        end
      end)

    query
    |> preload(^preload_items)
  end

  defp maybe_merge_dynamic_fields(query, fields) do
    fields
    |> Enum.reduce(query, fn
      {_name, %{display_field: _display_field}}, q ->
        q

      {name, %{select: select}}, q ->
        select_merge(q, ^%{name => select})

      _field, q ->
        q
    end)
  end
end
