%{
  configs: [
    %{
      name: :default,
      strict: false,
      color: true,
      checks: [
        {Credo.Check.Consistency.TabsOrSpaces},
        {Credo.Check.Readability.MaxLineLength, priority: :low, max_length: 100},
        {Credo.Check.Readability.AliasOrder, false},
        {Credo.Check.Readability.ModuleDoc, false},
        {Credo.Check.Readability.ModuleNames, false},
        {Credo.Check.Readability.Specs, false},
        {Credo.Check.Readability.SinglePipe, false},
        {Credo.Check.Refactor.Nesting, max_depth: 4},
        {Credo.Check.Refactor.RedundantWithClause, false},
        {Credo.Check.Refactor.LongQuoteBlocks, false},
        {Credo.Check.Refactor.FunctionArity, false},
        {Credo.Check.Refactor.CyclomaticComplexity, false},
        {Credo.Check.Design.TagTODO, false},
        {Credo.Check.Design.TagFIXME, false},
        {Credo.Check.Warning.IoInspect, false},
        {Credo.Check.Warning.IExPry, false},
        {Credo.Check.Warning.ExpensiveEmptyEnumCheck, false}
      ]
    }
  ]
}
