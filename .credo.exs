alias_usage_defaults = Credo.Check.Design.AliasUsage.param_defaults()

overwrite_checks = [
  {Credo.Check.Design.AliasUsage,
   excluded_namespaces: alias_usage_defaults[:excluded_namespaces] ++ ["Backpex.Fields"],
   excluded_lastnames: alias_usage_defaults[:excluded_lastnames] ++ ["Type"],
   if_nested_deeper_than: 2,
   if_called_more_often_than: 1},
  {Credo.Check.Design.TagTODO, false},
  {Credo.Check.Readability.AliasAs, false},
  {Credo.Check.Readability.OnePipePerLine, false},
  {Credo.Check.Readability.SinglePipe, false},
  {Credo.Check.Readability.Specs, false},
  {Credo.Check.Readability.StrictModuleLayout, ignore_module_attributes: ~w[config_schema resource_opts]a},
  {Credo.Check.Refactor.ABCSize, false},
  {Credo.Check.Refactor.ModuleDependencies, false},
  {Credo.Check.Refactor.PipeChainStart, false},
  {Credo.Check.Refactor.VariableRebinding, false},
  {Credo.Check.Warning.LazyLogging, false},
  {Credo.Check.Refactor.CondInsteadOfIfElse, false}
]

other_checks = [
  {PhoenixTest.Credo.NoOpenBrowser, []}
]

all_checks =
  Code.eval_file("deps/credo/.credo.exs")
  |> get_in([Access.elem(0), :configs, Access.at(0), :checks])
  |> then(fn checks -> checks.enabled ++ checks.disabled end)

project_checks =
  Enum.reduce(overwrite_checks, all_checks, fn {check, config}, acc ->
    Keyword.replace!(acc, check, config)
  end)
  |> Enum.concat(other_checks)

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
      requires: ["./deps/phoenix_test/lib/phoenix_test/credo/**/*.ex"],
      strict: true,
      parse_timeout: 5000,
      color: true,
      checks: project_checks
    }
  ]
}
