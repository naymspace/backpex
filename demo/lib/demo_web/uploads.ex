defmodule DemoWeb.Uploads do
  @moduledoc """
  Paths of the files that the upload fields of the demo store in `priv/static`.
  """

  def path(dir, file_name), do: Path.join([:code.priv_dir(:demo), "static", dir, file_name])
end
