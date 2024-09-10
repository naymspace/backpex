defmodule Demo.User do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Demo.Post
  alias Demo.UsersAddresses

  schema "users" do
    field :username, :string
    field :first_name, :string
    field :last_name, :string
    field :full_name, :string, virtual: true
    field :age, :integer
    field :role, Ecto.Enum, values: [:user, :admin]
    field :permissions, {:array, :string}
    field :avatar, :string
    field :deleted_at, :utc_datetime

    has_many :posts, Post, on_replace: :nilify
    has_many :users_addresses, UsersAddresses, on_replace: :delete, on_delete: :delete_all
    has_many :addresses, through: [:users_addresses, :address]

    embeds_many :social_links, SocialLink, on_replace: :delete do
      field :label, :string
      field :url, :string
    end

    embeds_many :web_links, WebLink, on_replace: :delete do
      field :label, :string
      field :url, :string
      field :notes, :string
    end

    timestamps()
  end

  @required_fields ~w[username first_name last_name role]a
  @optional_fields ~w[avatar deleted_at permissions age]a

  alias Demo.Repo
  import Ecto.Query

  @doc false
  def changeset(user, attrs, _metadata \\ []) do
    user
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> cast_assoc(:users_addresses, with: &UsersAddresses.changeset/2)
    |> cast_embed(:social_links,
      with: &social_links_changeset/2,
      sort_param: :social_links_order,
      drop_param: :social_links_delete
    )
    |> cast_embed(:web_links,
      with: &web_links_changeset/2,
      sort_param: :web_links_order,
      drop_param: :web_links_delete
    )
    |> validate_required(@required_fields)
    |> validate_length(:posts, min: 1)
    |> validate_change(:avatar, fn
      :avatar, "too_many_files" ->
        [avatar: "has to be exactly one"]

      :avatar, _avatar ->
        []
    end)
  end

  @required_fields ~w[label url]a

  def social_links_changeset(schema, attrs) do
    schema
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
  end

  @required_fields ~w[label url]a
  @optional_fields ~w[notes]a

  def web_links_changeset(schema, attrs) do
    schema
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end
