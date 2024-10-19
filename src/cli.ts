import { program } from 'commander';
import { readFileSync } from 'node:fs';
// @ts-ignore
import { type Ast, canonicalize } from './ast.ts';
// @ts-ignore
import * as usfm from './usfm/index.ts';
// @ts-ignore
import { html } from './render/html.ts';

program
	.description('render Bible file to HTML')
	.argument('<string>', 'filename')
	.option('-a, --ast', 'output ast instead of HTML')
	.option('-n, --no-normalize', 'do NOT normalize strings, remove extraneous elements')
	.action((fname, options) => {
		let ast: Ast;
		if (fname.endsWith('.usfm')) {
			const file = readFileSync(fname, 'utf8');
			ast = usfm.parseAndPrintErrors(file);
		} else {
			throw Error('unknown file type: ' + fname);
		}
		if (options.normalize) ast = canonicalize(ast);
		if (options.ast) {
			for (let i = 0; i < ast.length; i++) console.log(JSON.stringify(ast[i]));
		} else {
			html(s => process.stdout.write(s), ast);
		}
	});

program.parse();
