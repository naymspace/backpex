defmodule Backpex.Test.EctoFactory do
  @moduledoc """
  ExMachina factories for the schemas of the test app. Values are unique per sequence, so tests never depend on random
  data.
  """

  use ExMachina.Ecto, repo: Backpex.Test.Repo

  alias Backpex.Test.Address
  alias Backpex.Test.Category
  alias Backpex.Test.FilmReview
  alias Backpex.Test.Invoice
  alias Backpex.Test.Note
  alias Backpex.Test.Post
  alias Backpex.Test.Product
  alias Backpex.Test.Sample
  alias Backpex.Test.ShortLink
  alias Backpex.Test.Supplier
  alias Backpex.Test.Tag
  alias Backpex.Test.User

  def user_factory do
    %User{
      username: sequence(:username, &"user#{&1}"),
      first_name: sequence(:first_name, &"First#{&1}"),
      last_name: sequence(:last_name, &"Last#{&1}"),
      age: 30,
      role: :user,
      social_links: [%{label: "Website", url: "https://example.com/"}]
    }
  end

  def category_factory do
    %Category{name: sequence(:category_name, &"Category #{&1}")}
  end

  def tag_factory do
    %Tag{name: sequence(:tag_name, &"Tag #{&1}")}
  end

  def post_factory do
    %Post{
      title: sequence(:post_title, &"Post #{&1}"),
      body: "A post body.",
      published: true,
      user: build(:user),
      likes: 10,
      category: build(:category),
      tags: build_list(2, :tag)
    }
  end

  def supplier_factory do
    %Supplier{
      name: sequence(:supplier_name, &"Supplier #{&1}"),
      url: "https://example.com/",
      country: :Germany,
      contract_date: ~D[2025-01-01],
      minimum_order: 100_000,
      preferred: false
    }
  end

  def product_factory do
    %Product{
      name: sequence(:product_name, &"Product #{&1}"),
      quantity: 10,
      manufacturer: "https://example.com/",
      price: 1_000,
      suppliers: [],
      short_links: []
    }
  end

  def short_link_factory do
    %ShortLink{
      short_key: sequence(:short_key, &"key#{&1}"),
      url: "https://example.com/"
    }
  end

  def address_factory do
    %Address{
      street: sequence(:street, &"Street #{&1}"),
      zip: "12345",
      city: "Berlin",
      country: :de
    }
  end

  def film_review_factory do
    %FilmReview{
      title: sequence(:film_title, &"Film #{&1}"),
      overview: "An overview."
    }
  end

  def invoice_factory do
    %Invoice{
      company: sequence(:company, &"Company #{&1}"),
      amount: 1_000
    }
  end

  def note_factory do
    %Note{title: sequence(:note_title, &"Note #{&1}")}
  end

  def sample_factory do
    %Sample{text: sequence(:sample_text, &"Sample #{&1}")}
  end
end
