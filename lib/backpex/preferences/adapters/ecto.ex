defmodule Backpex.Preferences.Adapters.Ecto do
  @moduledoc """
  Database-backed `Backpex.Preferences` adapter, one row per preference key.

  Reach for this when you outgrow `Backpex.Preferences.Adapters.Session` — the
  default cookie store caps the whole session at ~4KB — or when preferences
  should follow a user across devices and browsers.

  You supply the table; Backpex supplies the adapter. There is no adapter
  module to write.

  ## Setup

  A migration and a schema, then one config entry.

      defmodule MyApp.Repo.Migrations.CreateBackpexUserPreferences do
        use Ecto.Migration

        def change do
          create table(:backpex_user_preferences) do
            add :user_id, references(:users, on_delete: :delete_all), null: false
            add :key,     :string, null: false
            add :value,   :map,    null: false, default: %{}
            timestamps(type: :utc_datetime_usec)
          end

          create unique_index(:backpex_user_preferences, [:user_id, :key])
        end
      end

      defmodule MyApp.Preferences.UserPreference do
        use Ecto.Schema

        schema "backpex_user_preferences" do
          field :user_id, :integer
          field :key,     :string
          field :value,   :map, default: %{}
          timestamps(type: :utc_datetime_usec)
        end
      end

      config :backpex, Backpex.Preferences,
        adapters: [
          {"resource.*", Backpex.Preferences.Adapters.Ecto,
           repo: MyApp.Repo, schema: MyApp.Preferences.UserPreference},
          {:default, Backpex.Preferences.Adapters.Session, []}
        ],
        identity: {MyAppWeb.PreferencesIdentity, :resolve, []}

  The unique index is required — writes upsert against it.

  ### Options

    * `:repo` — the `Ecto.Repo` to read and write through. Required.
    * `:schema` — the `Ecto.Schema` backing the preference table. Required.
    * `:identity_field` — the field holding the value returned by your identity
      resolver (default: `:user_id`). The `:key` and `:value` field names are
      fixed.

  ## Identity

  Every call needs a resolved identity. Configure an `:identity` resolver (see
  `Backpex.Preferences.Context`); without one, reads report nothing stored and
  writes fail with `{:error, :unidentified}` rather than writing rows nobody
  can read back.

  The `:identity_field` type must match whatever the resolver returns — a
  `:binary_id` user id needs a `:binary_id` column.

  ## How values are stored

  Preference values are frequently scalars: `metrics_visible` and every
  `global.sidebar_section.<id>` are booleans, `global.theme` is a string. A
  `:map` column cannot hold those, so every value is wrapped in a
  `%{"value" => term}` envelope on write and unwrapped on read. Rows are
  therefore `{"resource:MyApp.PostLive:columns", %{"value" => %{...}}}`, not a
  bare value — worth knowing when reading the table by hand.

  Keys are stored whole, one row each. `c:Backpex.Preferences.Adapter.get_map/3`
  rebuilds the nested shape it must return via
  `Backpex.Preferences.Adapter.nest/2`.

  ## Writes do not use your schema's `changeset/2`

  Rows are cast and inserted by this module, so a `changeset/2` on your schema
  is not consulted. That is deliberate: the adapter owns all three columns, and
  a host validation it cannot anticipate — a required field it does not set, a
  format check on `:key` — would fail every preference write with no way for
  the user to recover.

  Nothing is lost by it. The adapter never writes a partial row, and the upsert
  resolves conflicts in the database, so `validate_required/2` and
  `unique_constraint/3` on those columns can never fire on this path.

  Define a `changeset/2` anyway if you write these rows yourself elsewhere.
  """

  @behaviour Backpex.Preferences.Adapter

  import Ecto.Query

  alias Backpex.Preferences.Adapter
  alias Backpex.Preferences.Context
  alias Ecto.Changeset

  @envelope "value"

  @impl Adapter
  def get(%Context{identity: :unidentified}, _key, _opts), do: {:ok, :not_found}

  def get(%Context{identity: identity}, key, opts) do
    config = config(opts)

    query = from r in scope(config, identity), where: r.key == ^key, select: r.value

    case config.repo.one(query) do
      nil -> {:ok, :not_found}
      envelope -> {:ok, decode(envelope)}
    end
  end

  @impl Adapter
  def get_map(%Context{identity: :unidentified}, _prefix, _opts), do: {:ok, %{}}

  def get_map(%Context{identity: identity}, prefix, opts) do
    config = config(opts)

    # `LIKE` treats `_` in the pattern as a wildcard, so this can over-fetch.
    # `Adapter.nest/2` re-checks every row on parsed segments and drops the
    # ones that are not real descendants, so over-fetching is safe.
    query = from r in scope(config, identity), where: like(r.key, ^(prefix <> "%")), select: {r.key, r.value}

    rows =
      query
      |> config.repo.all()
      |> Enum.map(fn {key, envelope} -> {key, decode(envelope)} end)

    {:ok, Adapter.nest(rows, prefix)}
  end

  @impl Adapter
  def put(%Context{identity: :unidentified}, _key, _value, _opts), do: {:error, :unidentified}

  def put(%Context{identity: identity}, key, value, opts) do
    config = config(opts)

    params = %{config.identity_field => identity, :key => key, :value => encode(value)}

    config.schema
    |> struct()
    |> Changeset.cast(params, [config.identity_field, :key, :value])
    |> config.repo.insert!(
      on_conflict: {:replace, replaced_fields(config)},
      conflict_target: [config.identity_field, :key]
    )

    {:ok, :persisted}
  end

  defp config(opts) do
    %{
      repo: Keyword.fetch!(opts, :repo),
      schema: Keyword.fetch!(opts, :schema),
      identity_field: Keyword.get(opts, :identity_field, :user_id)
    }
  end

  defp scope(config, identity) do
    from r in config.schema, where: field(r, ^config.identity_field) == ^identity
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
