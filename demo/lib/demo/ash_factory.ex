defmodule Demo.AshFactory do
  @moduledoc false
  use Smokestack

  alias Demo.Helpdesk.Ticket

  factory Ticket do
    attribute :subject, &Faker.Lorem.sentence/0
    attribute :body, &Faker.Lorem.paragraph/0
  end
end
