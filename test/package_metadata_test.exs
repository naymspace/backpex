defmodule Backpex.PackageMetadataTest do
  use ExUnit.Case, async: true

  test "package.json version matches the Hex package version" do
    package_version =
      "package.json"
      |> File.read!()
      |> Jason.decode!()
      |> Map.fetch!("version")

    assert package_version == Mix.Project.config()[:version]
  end
end
