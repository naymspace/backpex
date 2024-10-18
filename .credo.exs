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
      checks: %{
        disabled: [],
        enabled: [
          {Credo.Check.Consistency.UnusedVariableNames, []}
        ]
      }
    }
  ]
}
