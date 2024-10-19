# bconv

[![GitHub license](https://img.shields.io/github/license/openbible-io/bconv?style=for-the-badge)](./LICENSE.md)
[![npm version](https://img.shields.io/npm/v/@openbible/bconv.svg?style=for-the-badge)](https://www.npmjs.com/package/@openbible/bconv)

Convert common Bible formats to a standard Ast. Available as a library or CLI.

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
> If you know of any ancient Biblical manuscripts that have _any_ formatting
> that does not fit this model, please file an issue and I will consider
> amending the model!
