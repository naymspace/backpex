defmodule Backpex.Test.Preferences.UserPreference do
  @moduledoc """
  Preference rows for the tests of `Backpex.Preferences.Adapters.Ecto` against PostgreSQL.
  """
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "backpex_user_preferences" do
    field :user_id, :integer
    field :tenant_id, :integer
    field :key, :string
    field :value, :map, default: %{}

    timestamps(type: :utc_datetime_usec)
  end
end
