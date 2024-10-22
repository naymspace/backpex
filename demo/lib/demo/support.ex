defmodule Demo.Helpdesk do
  @moduledoc false

  use Ash.Domain

  resources do
    resource Demo.Helpdesk.Ticket
  end
end
