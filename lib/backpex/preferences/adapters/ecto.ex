defmodule Backpex.Preferences.Adapters.Ecto do
  @moduledoc """
  Database-backed `Backpex.Preferences` adapter, one row per scoped preference
  key.

  Reach for this when preferences should follow a user across devices, need
  more room than the Session adapter's cookie budget, or belong to a compound
  namespace such as a user inside a tenant.

  You supply the table and the fields that make up its scope; Backpex supplies
  the adapter.

  ## Setup

      defmodule MyApp.Repo.Migrations.CreateBackpexPreferences do
        use Ecto.Migration

        def change do
          create table(:backpex_preferences) do
            add :user_id, references(:users, on_delete: :delete_all), null: false
            add :tenant_id, references(:tenants, on_delete: :delete_all), null: false
            add :key, :string, null: false
            add :value, :map, null: false, default: %{}
            timestamps(type: :utc_datetime_usec)
          end

          create unique_index(:backpex_preferences, [:user_id, :tenant_id, :key])
        end
      end

      defmodule MyApp.Preferences.Preference do
        use Ecto.Schema

        schema "backpex_preferences" do
          field :user_id, :integer
          field :tenant_id, :integer
          field :key, :string
          field :value, :map, default: %{}
          timestamps(type: :utc_datetime_usec)
        end
      end

      config :backpex, Backpex.Preferences,
        adapters: [
          {:default, Backpex.Preferences.Adapters.Ecto,
           repo: MyApp.Repo,
           schema: MyApp.Preferences.Preference,
           scope_fields: [:user_id, :tenant_id]}
        ],
        scope: {MyAppWeb.PreferencesScope, :resolve, []}

  The unique index must contain `scope_fields ++ [:key]` in the same order —
  writes use that list as their conflict target.

  ### Options

    * `:repo` — the `Ecto.Repo` to read and write through. Required.
    * `:schema` — the `Ecto.Schema` backing the preference table. Required.
    * `:scope_fields` — non-empty list of schema fields that identify the
      preference namespace. Required. The `:key` and `:value` field names are
      fixed.

  ## Scope

  Every call needs a resolved, non-empty atom-keyed scope map. Configure a
  `:scope` resolver (see `Backpex.Preferences.Context`) that returns at least
  every field listed in `:scope_fields`. Extra fields are ignored by this adapter, which lets two
  routes use different projections of one application-wide scope. For example,
  one adapter may use `[:user_id]` while another uses
  `[:user_id, :tenant_id]`.

  Without a usable scope, reads report nothing stored and writes fail with
  `{:error, :unscoped}` rather than writing rows nobody can read back. Missing
  configured fields return `{:error, {:invalid_scope, fields}}`.

  Scope field types must match the values returned by the resolver.

  ## How values are stored

  Preference values are frequently scalars: `metrics_visible` and every
  `global.sidebar_section.<id>` are booleans, `global.theme` is a string. A
  `:map` column cannot hold those, so every value is wrapped in a
  `%{"value" => term}` envelope on write and unwrapped on read.

  Keys are stored whole, one row each. `c:Backpex.Preferences.Adapter.get_map/3`
  rebuilds the nested shape it must return via
  `Backpex.Preferences.Adapter.nest/2`.

  ## Writes do not use your schema's `changeset/2`

  Rows are built with `Ecto.Changeset.change/2` and inserted by this module, so
  a `changeset/2` on your schema is not consulted. The adapter owns every
  field it writes and the database resolves conflicts atomically.
  """

  @behaviour Backpex.Preferences.Adapter

  import Ecto.Query

  alias Backpex.Preferences.Adapter
  alias Backpex.Preferences.Context
  alias Ecto.Changeset

  @envelope "value"
  @reserved_scope_fields [:key, :value]

  @impl Adapter
  def get(%Context{scope: scope}, _key, _opts) when scope in [nil, :unscoped], do: {:ok, :not_found}

  def get(%Context{scope: scope}, key, opts) when is_map(scope) do
    config = config(opts)

    with {:ok, scoped_values} <- scoped_values(scope, config.scope_fields) do
      query = from r in scope_query(config, scoped_values), where: r.key == ^key, select: r.value

      case config.repo.one(query) do
        nil -> {:ok, :not_found}
        envelope -> {:ok, decode(envelope)}
      end
    end
  end

  @impl Adapter
  def get_map(%Context{scope: scope}, _prefix, _opts) when scope in [nil, :unscoped], do: {:ok, %{}}

  def get_map(%Context{scope: scope}, prefix, opts) when is_map(scope) do
    config = config(opts)

    with {:ok, scoped_values} <- scoped_values(scope, config.scope_fields) do
      # `LIKE` treats `_` in the pattern as a wildcard, so this can over-fetch.
      # `Adapter.nest/2` re-checks every row on parsed segments and drops the
      # ones that are not real descendants, so over-fetching is safe.
      query =
        from r in scope_query(config, scoped_values),
          where: like(r.key, ^(prefix <> "%")),
          select: {r.key, r.value}

      rows =
        query
        |> config.repo.all()
        |> Enum.map(fn {key, envelope} -> {key, decode(envelope)} end)

      {:ok, Adapter.nest(rows, prefix)}
    end
  end

  @impl Adapter
  def put(%Context{scope: scope}, _key, _value, _opts) when scope in [nil, :unscoped], do: {:error, :unscoped}

  def put(%Context{scope: scope}, key, value, opts) when is_map(scope) do
    config = config(opts)

    with {:ok, scoped_values} <- scoped_values(scope, config.scope_fields) do
      changes = Map.merge(scoped_values, %{key: key, value: encode(value)})

      conflict_target =
        config.scope_fields
        |> Enum.reverse()
        |> then(&[:key | &1])
        |> Enum.reverse()

      config.schema
      |> struct()
      |> Changeset.change(changes)
      |> config.repo.insert!(
        on_conflict: {:replace, replaced_fields(config)},
        conflict_target: conflict_target
      )

      {:ok, :persisted}
    end
  end

  defp config(opts) do
    repo = Keyword.fetch!(opts, :repo)
    schema = Keyword.fetch!(opts, :schema)
    scope_fields = Keyword.fetch!(opts, :scope_fields)

    validate_scope_fields!(schema, scope_fields)

    %{repo: repo, schema: schema, scope_fields: scope_fields}
  end

  defp validate_scope_fields!(schema, scope_fields) when is_list(scope_fields) and scope_fields != [] do
    if !(Enum.all?(scope_fields, &is_atom/1) and Enum.uniq(scope_fields) == scope_fields) do
      raise ArgumentError, ":scope_fields must be a non-empty list of unique atoms"
    end

    validate_reserved_scope_fields!(scope_fields)
    validate_schema_fields!(schema, scope_fields)
  end

  defp validate_scope_fields!(_schema, _scope_fields) do
    raise ArgumentError, ":scope_fields must be a non-empty list of unique atoms"
  end

  defp validate_reserved_scope_fields!(scope_fields) do
    case Enum.filter(scope_fields, &(&1 in @reserved_scope_fields)) do
      [] -> :ok
      fields -> raise ArgumentError, ":scope_fields contains adapter-owned fields: #{inspect(fields)}"
    end
  end

  defp validate_schema_fields!(schema, scope_fields) do
    required_fields = scope_fields ++ @reserved_scope_fields
    unknown_fields = required_fields -- schema.__schema__(:fields)

    if unknown_fields != [] do
      raise ArgumentError,
            "unknown preference schema fields: #{inspect(unknown_fields)}; " <>
              "available fields: #{inspect(schema.__schema__(:fields))}"
    end
  end

  defp scoped_values(scope, scope_fields) do
    missing_fields = Enum.reject(scope_fields, &(Map.has_key?(scope, &1) and not is_nil(Map.get(scope, &1))))

    case missing_fields do
      [] -> {:ok, Map.take(scope, scope_fields)}
      fields -> {:error, {:invalid_scope, fields}}
    end
  end

  defp scope_query(config, scope) do
    Enum.reduce(config.scope_fields, config.schema, fn scope_field, query ->
      value = Map.fetch!(scope, scope_field)
      from r in query, where: field(r, ^scope_field) == ^value
    end)
  end

  # Only replace `:updated_at` when the schema actually has timestamps.
  defp replaced_fields(config) do
    if :updated_at in config.schema.__schema__(:fields) do
      [:value, :updated_at]
    else
      [:value]
    end
  end

  defp encode(value), do: %{@envelope => value}

  defp decode(%{@envelope => value}), do: value
end
