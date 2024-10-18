// @ts-ignore
import { Tokenizer, type Token } from './tokenizer.ts';
// @ts-ignore
import { Parser } from './parser.ts';

export { Tokenizer, Parser, type Token };

export function parse(usfm: string) {
	const tokenizer = new Tokenizer(usfm);
	return new Parser(tokenizer).document();
}
