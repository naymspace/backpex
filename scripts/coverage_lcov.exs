# Writes the coverage exported by `mix test --cover --export-coverage <name>` as cover/lcov.info for Codecov.
# `mix test.coverage` merges the exports into an HTML report only.
#
#     MIX_ENV=test mix run --no-start scripts/coverage_lcov.exs

root = File.cwd!()

# `mix test --cover` puts OTP's :tools application, which holds :cover, on the code path, `mix run` does not.
Mix.ensure_application!(:tools)
{:ok, _pid} = :cover.start()

case Path.wildcard("cover/*.coverdata") do
  [] -> Mix.raise("No coverage exports in cover/, run mix test --cover --export-coverage <name> first")
  files -> Enum.each(files, &(:ok = :cover.import(String.to_charlist(&1))))
end

# A module's source is only known once its BEAM file is loaded. Test support modules are left out.
lines_by_file =
  :cover.imported_modules()
  |> Enum.flat_map(fn module ->
    with {:module, ^module} <- Code.ensure_loaded(module),
         source when is_list(source) <- module.module_info(:compile)[:source],
         "lib/" <> _ = path <- Path.relative_to(List.to_string(source), root),
         {:ok, calls} <- :cover.analyse(module, :calls, :line) do
      for {{^module, line}, count} <- calls, line > 0, do: {path, line, count}
    else
      _other -> []
    end
  end)
  |> Enum.group_by(fn {path, _line, _count} -> path end, fn {_path, line, count} -> {line, count} end)

records =
  for {path, lines} <- Enum.sort(lines_by_file) do
    # Several modules of one file can report the same line.
    lines =
      lines
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Enum.map(fn {line, counts} -> {line, Enum.sum(counts)} end)
      |> Enum.sort()

    hit = Enum.count(lines, fn {_line, count} -> count > 0 end)

    [
      "SF:#{path}\n",
      Enum.map(lines, fn {line, count} -> "DA:#{line},#{count}\n" end),
      "LF:#{length(lines)}\nLH:#{hit}\nend_of_record\n"
    ]
  end

File.write!("cover/lcov.info", records)
Mix.shell().info("Wrote cover/lcov.info with #{length(records)} files")
