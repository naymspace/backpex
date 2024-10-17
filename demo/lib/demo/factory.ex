defmodule Demo.Factory do
  @moduledoc false

  use ExMachina.Ecto, repo: Demo.Repo

  alias Demo.Address
  alias Demo.Blog.Category
  alias Demo.Post
  alias Demo.Product
  alias Demo.ShortLink
  alias Demo.Supplier
  alias Demo.Tag
  alias Demo.User

  def user_factory do
    %User{
      username: Faker.Internet.user_name(),
      first_name: Faker.Person.first_name(),
      age: Enum.random(18..100),
      last_name: Faker.Person.last_name(),
      role: :user,
      social_links: generate_social_links()
    }
  end

  def generate_social_links do
    labels =
      ["Facebook", "LinkedIn", "Twitter", "YouTube", "TikTok", "Snapchat", "Instagram", "Pinterest"]
      |> Enum.shuffle()

    for index <- 0..Enum.random(0..3) do
      %{label: Enum.at(labels, index), url: "https://example.com/"}
    end
  end

  def category_factory do
    # TODO: change ash seeding?
    %Category{
      id: Ecto.UUID.generate(),
      name: Faker.Team.name(),
      inserted_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }
  end

  def tag_factory do
    %Tag{
      name: Faker.Team.name()
    }
  end

  def post_factory do
    %Post{
      title: Faker.App.name(),
      body: Faker.Lorem.paragraph(),
      published: boolean(),
      user: build(:user),
      likes: Enum.random(0..1_000),
      category: build(:category),
      tags: build_list(2, :tag)
    }
  end

  def supplier_factory do
    %Supplier{
      name: Faker.Company.name(),
      url: "https://example.com/"
    }
  end

  def product_factory do
    %Product{
      name: Faker.Food.ingredient(),
      quantity: Enum.random(0..1_000),
      manufacturer: "https://example.com/",
      price: Enum.random(50..5_000_000),
      suppliers: build_list(Enum.random(0..5), :supplier),
      short_links: build_list(Enum.random(0..5), :short_link)
    }
  end

  def short_link_factory do
    %ShortLink{
      short_key: ShortLink.generate_unique_short_key(),
      url: "https://example.com/"
    }
  end

  def address_factory do
    %Address{
      street: Faker.Address.street_address(),
      zip: Faker.Address.zip(),
      city: Faker.Address.city(),
      country: Enum.random([:de, :ch, :at])
    }
  end

  defp boolean do
    Enum.random(0..1) == 1
  end
end
