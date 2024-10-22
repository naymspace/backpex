defmodule Demo.Helpdesk do
  use Ash.Domain

  resources do
    resource Demo.Helpdesk.Ticket
  end
end
