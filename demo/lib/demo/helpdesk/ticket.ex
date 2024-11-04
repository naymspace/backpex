defmodule Demo.Helpdesk.Ticket do
  @moduledoc false

  use Ash.Resource,
    domain: Demo.Helpdesk,
    data_layer: AshPostgres.DataLayer

  postgres do
    repo Demo.RepoAsh
    table "tickets"
  end

  actions do
    defaults [:read]
  end

  attributes do
    uuid_primary_key :id
    attribute :subject, :string, allow_nil?: false
    attribute :body, :string, allow_nil?: false
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end
end
