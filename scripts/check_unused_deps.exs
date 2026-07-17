# Fails if a dependency is declared in mix.exs but never referenced by Backpex's code.
#
# Why this exists: `mix deps.unlock --check-unused` only compares mix.lock against
# mix.exs, so a dependency that is declared but never called looks perfectly used to
# it. That blind spot let :number sit unused from 71757de9 (2024-08-26) until it
# started blocking decimal 3.x — and with it ecto_sql — about two years later.
#
# How it works: the modules of each dependency are looked up via its application
# spec and matched against the module references in Backpex's own BEAM files. Both
# the imports table (remote calls) and literal atoms (behaviours, structs, module
# names passed around as values) are considered, which keeps false positives low.
#
# Dependencies that are legitimately never referenced by name — protocol
# implementations, runtime drivers — belong in @allowlist together with a reason.
#
# Run via: mix deps.unused

defmodule CheckUnusedDeps do
  @allowlist %{
    phoenix_ecto:
      "Provides protocol implementations (Phoenix.HTML.FormData for Ecto.Changeset) " <>
        "that are resolved at runtime and are never referenced by name."
  }

  def run do
    app = Mix.Project.config()[:app]
    referenced = referenced_modules(app)
    deps = deps_to_check()

    case Enum.filter(deps, &unused?(&1, referenced)) do
      [] ->
        IO.puts("Checked #{length(deps)} dependencies, all are referenced.")
        # Keep the allowlist visible: an exemption nobody sees is how an unused
        # dependency hides in the first place.
        for {dep, reason} <- @allowlist, do: IO.puts("Allowlisted: #{dep} — #{reason}")
        :ok

      unused ->
        report(unused)
        exit({:shutdown, 1})
    end
  end

  # Dependencies that ship with the package. Dev/test-only tooling is irrelevant here:
  # it is never part of what a Backpex user resolves.
  defp deps_to_check do
    Mix.Project.config()[:deps]
    |> Enum.map(fn
      {name, opts} when is_list(opts) -> {name, opts}
      {name, _req} -> {name, []}
      {name, _req, opts} -> {name, opts}
    end)
    |> Enum.reject(fn {name, opts} ->
      dev_or_test_only?(opts) or Map.has_key?(@allowlist, name)
    end)
    |> Enum.map(fn {name, _opts} -> name end)
  end

  defp dev_or_test_only?(opts) do
    case opts[:only] do
      nil -> false
      only -> :prod not in List.wrap(only)
    end
  end

  defp unused?(dep, referenced) do
    case modules(dep) do
      # A dependency without an application spec cannot be judged, so leave it alone
      # rather than report something we did not actually verify.
      [] -> false
      modules -> not Enum.any?(modules, &MapSet.member?(referenced, &1))
    end
  end

  defp modules(dep) do
    Application.load(dep)
    Application.spec(dep, :modules) || []
  end

  defp referenced_modules(app) do
    "_build/#{Mix.env()}/lib/#{app}/ebin/*.beam"
    |> Path.wildcard()
    |> Enum.reduce(MapSet.new(), fn beam, acc ->
      {:ok, {_module, chunks}} = :beam_lib.chunks(String.to_charlist(beam), [:imports, :atoms])

      imports = for {module, _fun, _arity} <- Keyword.get(chunks, :imports, []), do: module
      atoms = for {_index, atom} <- Keyword.get(chunks, :atoms, []), is_atom(atom), do: atom

      acc |> MapSet.union(MapSet.new(imports)) |> MapSet.union(MapSet.new(atoms))
    end)
  end

  defp report(unused) do
    IO.puts("""

    Unused dependencies found — declared in mix.exs, but no module of them is
    referenced anywhere in lib/:

    #{Enum.map_join(unused, "\n", &"  * #{&1}")}

    Remove them from mix.exs. If a dependency is used without being referenced by
    name — a protocol implementation or a runtime driver, for example — add it to
    @allowlist in scripts/check_unused_deps.exs together with the reason.
    """)
  end
end

CheckUnusedDeps.run()
