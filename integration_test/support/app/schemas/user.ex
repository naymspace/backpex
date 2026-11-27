defmodule Backpex.Test.User do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Backpex.Test.Post
  alias Backpex.Test.UsersAddresses

  schema "users" do
    field :username, :string
    field :first_name, :string
    field :last_name, :string
    field :full_name, :string, virtual: true
    field :age, :integer
    field :role, Ecto.Enum, values: [:user, :admin]
    field :avatar, :string
    field :deleted_at, :utc_datetime

    has_many :posts, Post, on_replace: :nilify
    has_many :users_addresses, UsersAddresses, on_replace: :delete, on_delete: :delete_all
    has_many :addresses, through: [:users_addresses, :address]

    embeds_many :social_links, SocialLink, on_replace: :delete do
      field :label, :string
      field :url, :string
    end

    embeds_one :emergency_contact, EmergencyContact do
      field :name, :string
      field :phone, :string
    end

    timestamps()
  end

  @required_fields ~w[username first_name last_name role]a
  @optional_fields ~w[age avatar deleted_at]a

  def changeset(user, attrs, _metadata \\ []) do
    user
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> cast_assoc(:users_addresses, with: &UsersAddresses.changeset/2)
    |> cast_embed(:social_links,
      with: &social_links_changeset/2,
      sort_param: :social_links_order,
      drop_param: :social_links_delete
    )
    |> cast_embed(:emergency_contact, with: &emergency_contact_changeset/2)
    |> validate_required(@required_fields)
  end

  def social_links_changeset(social_link, attrs) do
    social_link
    |> cast(attrs, [:label, :url])
    |> validate_required([:label, :url])
  end

  def emergency_contact_changeset(emergency_contact, attrs) do
    cast(emergency_contact, attrs, [:name, :phone])
  end
end
