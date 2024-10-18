# bconv

Convert common Bible formats to a standard AST. Available as a library or CLI.

## Goals
- Small code size for web use and long-term maintainability
- Use tokenizer (for syntax highlighting in an editor)
- Work on real-world publications

## Non-goals
- Complete (ignores most element types)
- Render nicely
- Natural language processing

## Ast
See [the type.](./src/ast.ts)

> [!NOTE]
> If you know of any ancient Biblical manuscripts that have _any_ formatting that does not fit
> this model, please file an issue and I will amend the model!
