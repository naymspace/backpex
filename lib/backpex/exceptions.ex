defmodule Backpex.NoResultsError do
  @moduledoc """
  Raised when no results can be found.
  """

  defexception message: "No results could be found", plug_status: 404
end

defmodule Backpex.ForbiddenError do
  @moduledoc """
  Raised when action can not be performed due to missing permission.

  If you are seeing this error, you should check if you have the permission necessary to perform the action.
  """

  defexception message: "Forbidden", plug_status: 403

  def exception(_opts) do
    %__MODULE__{message: "Forbidden"}
  end
end
