defmodule Backpex.Test.Uploads do
  @moduledoc """
  The directory the upload fields of the test app store their files in. `Backpex.Test.Endpoint` serves its `uploads`
  subdirectory. Each `MIX_TEST_PARTITION` has its own directory, which `test_helper.exs` empties on every run.
  """

  def dir, do: Path.expand("../../../tmp/static#{System.get_env("MIX_TEST_PARTITION")}", __DIR__)
end
