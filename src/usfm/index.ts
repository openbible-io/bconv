// @ts-ignore
import { Tokenizer, type Token } from './tokenizer.ts';
// @ts-ignore
import { Parser } from './parser.ts';
import chalk from 'chalk';

export { Tokenizer, Parser, type Token };

const theme = {
	error: chalk.bold.red,
	token: chalk.blue,
	warnToken: chalk.green,
	lineno: chalk.grey,
};

function lineNo(file: string, tok: Token) {
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

function printToken(file: string, tok: Token) {
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


export function parse(usfm: string) {
	const tokenizer = new Tokenizer(usfm);
	return new Parser(tokenizer).document();
}

export function parseAndPrintErrors(usfm: string) {
	const document = parse(usfm);
	const ast = document.ast;
	for (let i = 0; i < document.errors.length; i++) {
		const err = document.errors[i];
		if (typeof err.kind == 'object') {
			const tag = Object.keys(err.kind)[0];

			if (tag == 'expected_self_close') {
				console.warn('Expected', theme.warnToken('\\*'), 'here:');
				printToken(usfm, err.token);
				const tag = usfm.substring(
					err.kind.expected_self_close.start,
					err.kind.expected_self_close.end,
				);
				console.warn('For', theme.warnToken(tag), 'tag that opened here:');
				printToken(usfm, err.kind.expected_self_close);
				console.warn();
			} else {
				console.error('dunno how to fmt');
			}
		} else {
			console.warn(err.kind);
			printToken(usfm, err.token);
		}
	}
	return ast;
}
