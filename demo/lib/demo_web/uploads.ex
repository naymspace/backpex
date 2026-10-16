defmodule DemoWeb.Uploads do
  @moduledoc """
  Paths of the files that the upload fields of the demo store.

  The files go to `priv/static`, unless `:upload_root` of the `:demo` app names another directory (the tests use a
  temporary one).
  """

  def path(dir, file_name), do: Path.join([root(), dir, file_name])

  defp root, do: Application.get_env(:demo, :upload_root) || static_dir()

  defp static_dir do
    :demo
    |> :code.priv_dir()
    |> Path.join("static")
  end
end
