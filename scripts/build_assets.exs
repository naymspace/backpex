# Bundles the hooks in assets/js into priv/static/js with the esbuild profiles of config/config.exs. Each bundle ends
# with the license files of the third-party packages it includes, in a legal comment (`/*!`) that the bundlers of
# Backpex users keep, so a new dependency needs no manual notice.
#
#     mix assets.build   # builds both bundles
#     mix assets.watch   # rebuilds the ESM bundle on changes

esbuild = fn profile, args -> Mix.Task.rerun("esbuild", [profile | args]) end

# A first build writes esbuild's metafile, which lists the bundled files with paths relative to assets/.
metafile = Path.join(Mix.Project.build_path(), "esbuild.meta.json")
esbuild.("module", ["--metafile=" <> metafile])

license_notice = fn package_dir ->
  package = package_dir |> Path.join("package.json") |> File.read!() |> Jason.decode!()

  license_file =
    package_dir
    |> File.ls!()
    |> Enum.sort()
    |> Enum.find(&(&1 =~ ~r/^(licen[cs]e|copying)/i)) ||
      Mix.raise("#{package["name"]} is bundled but ships no license file to copy into the bundle")

  text = package_dir |> Path.join(license_file) |> File.read!() |> String.trim() |> String.replace("*/", "* /")

  "#{package["name"]} #{package["version"]} (#{package["license"]})\n\n#{text}"
end

notices =
  metafile
  |> File.read!()
  |> Jason.decode!()
  |> Map.fetch!("inputs")
  |> Map.keys()
  |> Enum.flat_map(&(Regex.run(~r{^.*node_modules/(@[^/]+/)?[^/]+}, &1, capture: :first) || []))
  |> Enum.uniq()
  |> Enum.sort()
  |> Enum.map(&license_notice.(Path.expand(&1, "assets")))

footer =
  case notices do
    [] -> ""
    notices -> "/*! Licenses of the third-party packages in this bundle\n\n" <> Enum.join(notices, "\n\n") <> "\n*/"
  end

case System.argv() do
  ["--watch"] ->
    esbuild.("module", ["--watch", "--footer:js=" <> footer])

  [] ->
    esbuild.("module", ["--footer:js=" <> footer])
    esbuild.("main", ["--footer:js=" <> footer])
end
