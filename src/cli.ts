import { program } from 'commander';
import { readFileSync } from 'node:fs';
import chalk from 'chalk';
// @ts-ignore
import { type Ast, canonicalize } from './ast.ts';
// @ts-ignore
import * as usfm from './usfm/index.ts';
// @ts-ignore
import { html } from './render/html.ts';

const theme = {
	error: chalk.bold.red,
	token: chalk.blue,
	warnToken: chalk.green,
	lineno: chalk.grey,
};

function lineNo(file: string, tok: usfm.Token) {
	let line = 1;
	let pos = 0;
	for (let i = 0; i < tok.start; i++) {
		if (file[i] == '\n') {
			line++;
			pos = i + 1;
		}
	}
	return { line, pos } ;
}

function printToken(file: string, tok: usfm.Token) {
	const { line, pos: lineStart } = lineNo(file, tok);
	let lineEnd = tok.end - 1;
	while (file[lineEnd] != '\n' && lineEnd < file.length) lineEnd += 1;

	let tokEnd = file.substring(lineStart, tok.end).indexOf('\n');
	if (tokEnd == -1) tokEnd = tok.end;
	else tokEnd += lineStart;

	process.stderr.write(theme.lineno(line + '|'));
	process.stderr.write(file.substring(lineStart, tok.start));
	process.stderr.write(theme.token(file.substring(tok.start, tokEnd)));
	if (tokEnd == tok.end) process.stderr.write(file.substring(tok.end, lineEnd));
	process.stderr.write('\n');
}

program
	.description('render a file to html')
	.argument('<string>', 'filename')
	.option('-a, --ast', 'output ast instead of HTML')
	.option('-n, --no-normalize', 'do NOT normalize strings, remove extraneous elements')
	.action((fname, options) => {
		let ast: Ast;
		if (fname.endsWith('.usfm')) {
			const file = readFileSync(fname, 'utf8');
			const document = usfm.parse(file);
			ast = document.ast;
			for (let i = 0; i < document.errors.length; i++) {
				const err = document.errors[i];
				if (typeof err.kind == 'object') {
					const tag = Object.keys(err.kind)[0];

					if (tag == 'expected_self_close') {
						console.warn('Expected', theme.warnToken('\\*'), 'here:');
						printToken(file, err.token);
						const tag = file.substring(
							err.kind.expected_self_close.start,
							err.kind.expected_self_close.end,
						);
						console.warn('For', theme.warnToken(tag), 'tag that opened here:');
						printToken(file, err.kind.expected_self_close);
						console.warn();
					} else {
						console.error('dunno how to fmt');
					}
				} else {
					console.warn(err.kind);
					printToken(file, err.token);
				}
			}
		} else {
			throw Error('unknown file type: ' + fname);
		}
		if (options.normalize) ast = canonicalize(ast);
		if (options.ast) {
			for (let i = 0; i < ast.length; i++) console.log(JSON.stringify(ast[i]));
			return;
		}
		html(ast);
	});

program.parse();
