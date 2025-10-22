defmodule Demo.EctoFactory do
  @moduledoc false

  use ExMachina.Ecto, repo: Demo.Repo

  alias Demo.Address
  alias Demo.Category
  alias Demo.Entity
  alias Demo.FilmReview
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

  def category_factory do
    %Category{
      name: Faker.Team.name()
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
      more_info: %{
        weight: Enum.random(1..100),
        goes_well_with: Faker.Food.description()
      },
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

  def film_review_factory do
    %FilmReview{
      title: Faker.Lorem.word(),
      overview: Faker.Lorem.paragraph()
    }
  end

  defp boolean do
    Enum.random(0..1) == 1
  end

  defp generate_social_links do
    labels =
      ["Facebook", "LinkedIn", "Twitter", "YouTube", "TikTok", "Snapchat", "Instagram", "Pinterest"]
      |> Enum.shuffle()

    for index <- 0..Enum.random(0..3) do
      %{label: Enum.at(labels, index), url: "https://example.com/"}
    end
  end

  def car_factory do
    %Entity{
      identity: Faker.Vehicle.En.make_and_model(),
      type: "car",
      fields: %{
        "engine_size" => Enum.random([1800, 2000, 2300, 2500, 3000, 3400, 4000, 5000]),
        "colour" => Faker.Color.En.name(),
        "year" => Enum.random(1900..2025)
      }
    }
  end

  def person_factory do
    first_name = Faker.Person.first_name()
    last_name = Faker.Person.last_name()

    %Entity{
      identity: "#{first_name} #{last_name}",
      type: "person",
      fields: %{
        "email" => Faker.Internet.email(),
        "phone" => Faker.Phone.number(),
        "age" => Enum.random(18..85),
        "weight" => Enum.random(45..130)
      }
    }
  end
end
