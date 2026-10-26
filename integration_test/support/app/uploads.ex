defmodule Backpex.Test.Uploads do
  @moduledoc """
  The directory the upload fields of the test app store their files in. `Backpex.Test.Endpoint` serves its `uploads`
  subdirectory.
  """

  @dir Path.expand("../../../tmp/static", __DIR__)

  def dir, do: @dir
end
