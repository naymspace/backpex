defmodule Demo.Preferences.UserPreference do
  @moduledoc """
  Preference rows for `Backpex.Preferences.Adapters.Ecto`.

  The demo routes preferences to the session adapter; this table exists so the
  shipped Ecto adapter has real SQL to run against in the test suite, which the
  library's own suite cannot provide (it has no repo).
  """
  use Ecto.Schema

  # The demo's migrations default to `binary_id` primary keys, so the schema has
  # to generate one; the column has no database-side default.
  @primary_key {:id, :binary_id, autogenerate: true}

  schema "backpex_user_preferences" do
    field :user_id, :integer
    field :key, :string
    field :value, :map, default: %{}

    timestamps(type: :utc_datetime_usec)
  end
end
