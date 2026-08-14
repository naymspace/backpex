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
           scope_fields: [:user_id, :tenant_id],
           storage_key_prefix: "backpex."}
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
    * `:storage_key_prefix` — string prepended to keys in the database and
      removed again on reads. Defaults to `""`. The value is used exactly as
      configured, so include any separator you want in storage, for example
      `"backpex."`.
    * `:max_key_bytes` — upper bound for the byte size of a stored key
      (prefix included), or `:infinity`. Defaults to `255`, matching the
      `varchar(255)` column the documented migration creates. Longer keys are
      refused with `{:error, :key_too_long}` instead of surfacing as a
      database error.
    * `:max_value_bytes` — write budget for a single value, or `:infinity`.
      Defaults to `65536`. Values are measured via `:erlang.external_size/1`
      of the stored envelope — an approximation of the row's storage
      footprint, which is the right direction for a budget check. Oversized
      values are refused with `{:error, :too_large}`.
    * `:max_keys` — how many distinct keys one scope may hold, or
      `:infinity`. Defaults to `1000`. Writes that would create a row beyond
      the cap are refused with `{:error, :too_many_keys}`; updates to
      existing keys always go through.

  ## Write limits

  Preference writes arrive from the browser, so without a ceiling a single
  authenticated caller could grow the table without bound — the
  `Backpex.Preferences.Keys` gate checks value *shape* for built-in keys, not
  size, and keys Backpex does not own pass through unchecked. The three limit
  options above close that hole with defaults far beyond what legitimate
  Backpex traffic writes (a handful of small maps per resource). A refusal
  surfaces to the client as a `422` from `Backpex.PreferencesController`, the
  same designed outcome as the Session adapter's `{:error, :too_large}`.

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

  require Logger

  @envelope "value"
  @reserved_scope_fields [:key, :value]

  # The documented migration stores keys in a `:string` column — varchar(255).
  @default_max_key_bytes 255
  @default_max_value_bytes 65_536
  @default_max_keys 1_000

  @impl Adapter
  def get(%Context{scope: scope}, _key, _opts) when scope in [nil, :unscoped], do: {:ok, :not_found}

  def get(%Context{scope: scope}, key, opts) when is_map(scope) do
    config = config(opts)

    with {:ok, scoped_values} <- scoped_values(scope, config.scope_fields) do
      query =
        from r in scope_query(config, scoped_values),
          where: r.key == ^storage_key(config, key),
          select: r.value

      case config.repo.one(query) do
        nil -> {:ok, :not_found}
        envelope -> {:ok, decode(envelope)}
      end
    end
  end

  @impl Adapter
  def client_namespace(%Context{scope: scope}, _opts) when scope in [nil, :unscoped], do: {:error, :unscoped}

  def client_namespace(%Context{scope: scope}, opts) when is_map(scope) do
    config = config(opts)

    with {:ok, scoped_values} <- scoped_values(scope, config.scope_fields) do
      {:ok, {config.repo, config.schema, config.storage_key_prefix, scoped_values}}
    end
  end

  @impl Adapter
  def get_map(%Context{scope: scope}, _prefix, _opts) when scope in [nil, :unscoped], do: {:ok, %{}}

  def get_map(%Context{scope: scope}, prefix, opts) when is_map(scope) do
    config = config(opts)

    with {:ok, scoped_values} <- scoped_values(scope, config.scope_fields) do
      storage_prefix = storage_key(config, prefix)

      # `LIKE` treats `_` in the pattern as a wildcard, so this can over-fetch.
      # `Adapter.nest/2` re-checks every row on parsed segments and drops the
      # ones that are not real descendants, so over-fetching is safe.
      query =
        from r in scope_query(config, scoped_values),
          where: like(r.key, ^(storage_prefix <> "%")),
          select: {r.key, r.value}

      rows =
        query
        |> config.repo.all()
        |> Enum.filter(fn {key, _envelope} -> String.starts_with?(key, storage_prefix) end)
        |> Enum.map(fn {key, envelope} -> {logical_key(config, key), decode(envelope)} end)

      {:ok, Adapter.nest(rows, prefix)}
    end
  end

  @impl Adapter
  def put(%Context{scope: scope}, _key, _value, _opts) when scope in [nil, :unscoped], do: {:error, :unscoped}

  def put(%Context{scope: scope}, key, value, opts) when is_map(scope) do
    config = config(opts)
    storage_key = storage_key(config, key)

    with {:ok, scoped_values} <- scoped_values(scope, config.scope_fields),
         :ok <- refuse_oversized_key(config, key, storage_key),
         :ok <- refuse_oversized_value(config, key, value),
         :ok <- refuse_exceeded_key_quota(config, scoped_values, storage_key, key) do
      changes = Map.merge(scoped_values, %{key: storage_key, value: encode(value)})

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

  defp refuse_oversized_key(%{max_key_bytes: :infinity}, _key, _storage_key), do: :ok

  defp refuse_oversized_key(config, key, storage_key) do
    if byte_size(storage_key) <= config.max_key_bytes do
      :ok
    else
      Logger.warning(
        "Backpex.Preferences: refusing the write to #{inspect(key)}: the storage key is " <>
          "#{byte_size(storage_key)} bytes, over the #{config.max_key_bytes} byte `:max_key_bytes` limit."
      )

      {:error, :key_too_long}
    end
  end

  defp refuse_oversized_value(%{max_value_bytes: :infinity}, _key, _value), do: :ok

  defp refuse_oversized_value(config, key, value) do
    size = value |> encode() |> :erlang.external_size()

    if size <= config.max_value_bytes do
      :ok
    else
      Logger.warning(
        "Backpex.Preferences: refusing the write to #{inspect(key)}: the value measures " <>
          "~#{size} bytes, over the #{config.max_value_bytes} byte `:max_value_bytes` budget. " <>
          "Raise the limit if per-key data this large is intended."
      )

      {:error, :too_large}
    end
  end

  defp refuse_exceeded_key_quota(%{max_keys: :infinity}, _scoped_values, _storage_key, _key), do: :ok

  defp refuse_exceeded_key_quota(config, scoped_values, storage_key, key) do
    exists_query =
      from r in scope_query(config, scoped_values),
        where: r.key == ^storage_key,
        select: true

    cond do
      config.repo.one(exists_query) ->
        :ok

      key_count(config, scoped_values) < config.max_keys ->
        :ok

      true ->
        Logger.warning(
          "Backpex.Preferences: refusing the write to #{inspect(key)}: this scope already holds " <>
            "#{config.max_keys} keys (`:max_keys`). Raise the limit if a scope legitimately needs more."
        )

        {:error, :too_many_keys}
    end
  end

  defp key_count(config, scoped_values) do
    config
    |> scope_query(scoped_values)
    |> config.repo.aggregate(:count)
  end

  defp config(opts) do
    repo = Keyword.fetch!(opts, :repo)
    schema = Keyword.fetch!(opts, :schema)
    scope_fields = Keyword.fetch!(opts, :scope_fields)
    storage_key_prefix = Keyword.get(opts, :storage_key_prefix, "")
    max_key_bytes = Keyword.get(opts, :max_key_bytes, @default_max_key_bytes)
    max_value_bytes = Keyword.get(opts, :max_value_bytes, @default_max_value_bytes)
    max_keys = Keyword.get(opts, :max_keys, @default_max_keys)

    validate_scope_fields!(schema, scope_fields)
    validate_storage_key_prefix!(storage_key_prefix)
    validate_limit!(:max_key_bytes, max_key_bytes)
    validate_limit!(:max_value_bytes, max_value_bytes)
    validate_limit!(:max_keys, max_keys)

    %{
      repo: repo,
      schema: schema,
      scope_fields: scope_fields,
      storage_key_prefix: storage_key_prefix,
      max_key_bytes: max_key_bytes,
      max_value_bytes: max_value_bytes,
      max_keys: max_keys
    }
  end

  defp validate_limit!(_name, limit) when is_integer(limit) and limit > 0, do: :ok
  defp validate_limit!(_name, :infinity), do: :ok

  defp validate_limit!(name, limit) do
    raise ArgumentError, "#{inspect(name)} must be a positive integer or :infinity, got: #{inspect(limit)}"
  end

  defp validate_storage_key_prefix!(storage_key_prefix) when is_binary(storage_key_prefix), do: :ok

  defp validate_storage_key_prefix!(_storage_key_prefix) do
    raise ArgumentError, ":storage_key_prefix must be a string"
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

  defp storage_key(config, key), do: config.storage_key_prefix <> key
  defp logical_key(config, key), do: String.replace_prefix(key, config.storage_key_prefix, "")

  defp encode(value), do: %{@envelope => value}

  defp decode(%{@envelope => value}), do: value
end
