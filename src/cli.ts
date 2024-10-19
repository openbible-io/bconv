import { stdout } from 'node:process';
import { program } from 'commander';
import { type Ast, canonicalize } from './ast.ts';
import * as lib from './index.ts';

program
	.description('render Bible file to HTML')
	.argument('<string>', 'filename')
	.option('-a, --ast', 'output ast instead of HTML')
	.option(
		'-n, --no-normalize',
		'do NOT normalize strings, remove extraneous elements',
	)
	.action((fname, options) => {
		let ast: Ast;
		if (fname.endsWith('.usfm')) {
			const file = Deno.readTextFileSync(fname);
			ast = lib.usfm.parseAndPrintErrors(file);
		} else {
			throw Error('unknown file type: ' + fname);
		}
		if (options.normalize) ast = canonicalize(ast);
		if (options.ast) {
			for (let i = 0; i < ast.length; i++) console.log(JSON.stringify(ast[i]));
		} else {
			lib.render.html((s: string) => stdout.write(s), ast);
		}
	});

program.parse();
