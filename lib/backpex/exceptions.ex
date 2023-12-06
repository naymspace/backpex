defmodule Backpex.NoResourceError do
  @moduledoc """
  Raised when resource can not be found.

  If you are seeing this error, you should check if you provided the correct identifier for the requested resource.
  """

  defexception message: "Resource not found", plug_status: 404

  def exception(opts) do
    name = Keyword.fetch!(opts, :name)
    %__MODULE__{message: "no resource found for:\n\n#{inspect(name)}"}
  end
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
