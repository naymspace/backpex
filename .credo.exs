overwrite_checks = [
  {Credo.Check.Design.TagTODO, false},
  {Credo.Check.Readability.AliasAs, false},
  {Credo.Check.Readability.OnePipePerLine, false},
  {Credo.Check.Readability.SinglePipe, false},
  {Credo.Check.Readability.Specs, false},
  {Credo.Check.Readability.StrictModuleLayout, ignore_module_attributes: ~w[config_schema]a},
  {Credo.Check.Refactor.ABCSize, false},
  {Credo.Check.Refactor.ModuleDependencies, false},
  {Credo.Check.Refactor.PipeChainStart, false},
  {Credo.Check.Refactor.VariableRebinding, false},
  {Credo.Check.Warning.LazyLogging, false}
]

all_checks =
  Code.eval_file("deps/credo/.credo.exs")
  |> get_in([Access.elem(0), :configs, Access.at(0), :checks])
  |> then(fn checks -> checks.enabled ++ checks.disabled end)

project_checks =
  Enum.reduce(overwrite_checks, all_checks, fn {check, config}, acc ->
    Keyword.replace(acc, check, config)
  end)

%{
  configs: [
    %{
      name: "default",
      files: %{
        included: [
          "lib/",
          "test/",
          "priv/"
        ],
        excluded: [~r"/_build/", ~r"/deps/", ~r"/node_modules/"]
      },
      plugins: [],
      requires: [],
      strict: true,
      parse_timeout: 5000,
      color: true,
      checks: project_checks
    }
  ]
}
