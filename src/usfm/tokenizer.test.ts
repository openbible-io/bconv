import { expect, test } from "bun:test";
import { type Token, Tokenizer } from "./tokenizer.ts";

function collectTokens(s: string) {
	const tokenizer = new Tokenizer(s);
	const res: Token[] = [];

	let t: Token;
	while ((t = tokenizer.next()).tag != "eof") res.push(t);

	return res;
}

type Expected = { tag: string; text?: string };
function expectTokens(s: string, expected: Expected[]) {
	collectTokens(s).forEach((actual, i) => {
		const exp = expected[i];
		if (exp.text) {
			const text = s.substring(actual.start, actual.end);
			expect(text).toBe(exp.text);
		}
		expect(actual.tag).toBe(exp.tag);
	});
}

test("single simple tag", () => {
	expectTokens("\\id GEN EN_ULT en_English_ltr", [
		{ tag: "tag_open", text: "\\id" },
		{ tag: "text", text: "GEN EN_ULT en_English_ltr" },
	]);
});

test("two simple tags", () => {
	const s = `\\id GEN EN_ULT en_English_ltr
\\usfm 3.0`;
	expectTokens(s, [
		{ tag: "tag_open" },
		{ tag: "text", text: "GEN EN_ULT en_English_ltr\n" },
		{ tag: "tag_open" },
		{ tag: "text" },
	]);
});

test("single attribute tag", () => {
	const s = '\\word hello |   x-occurences  =   "1"\\word*';
	expectTokens(s, [
		{ tag: "tag_open", text: "\\word" },
		{ tag: "text", text: "hello " },
		{ tag: "attribute_start", text: "|" },
		{ tag: "id", text: "x-occurences" },
		{ tag: "kv_sep", text: "=" },
		{ tag: "id", text: "1" },
		{ tag: "tag_close", text: "\\word*" },
	]);
});

test("empty attribute tag", () => {
	const s = `\\word hello|\\word*`;
	expectTokens(s, [
		{ tag: "tag_open" },
		{ tag: "text" },
		{ tag: "attribute_start" },
		{ tag: "tag_close" },
	]);
});

test("attributes with spaces", () => {
	const s = `\\zaln-s|x-lemma="a b" x-abc="123" \\*\\zaln-e\\*`;
	expectTokens(s, [
		{ tag: "tag_open" },
		{ tag: "attribute_start" },
		{ tag: "id", text: "x-lemma" },
		{ tag: "kv_sep" },
		{ tag: "id", text: "a b" },
		{ tag: "id", text: "x-abc" },
		{ tag: "kv_sep" },
		{ tag: "id", text: "123" },
		{ tag: "tag_close" },
		{ tag: "tag_open" },
		{ tag: "tag_close" },
	]);
});

test("milestones", () => {
	const s = `\\v 1 \\zaln-s\\*\\w In\\w*\\zaln-e\\*there`;
	expectTokens(s, [
		{ tag: "tag_open" },
		{ tag: "text" },
		{ tag: "tag_open" },
		{ tag: "tag_close" },
		{ tag: "tag_open" },
		{ tag: "text" },
		{ tag: "tag_close" },
		{ tag: "tag_open" },
		{ tag: "tag_close" },
		{ tag: "text" },
	]);
});

test("self closing tag", () => {
	expectTokens(`\\zaln-s hello\\*`, [
		{ tag: "tag_open", text: "\\zaln-s" },
		{ tag: "text", text: "hello" },
		{ tag: "tag_close", text: "\\*" },
	]);
});

test("line breaks", () => {
	const s = `\\v 1 \\w In\\w*
\\w the\\w* 012
\\w beginning\\w*.`;

	expectTokens(s, [
		{ tag: "tag_open" },
		{ tag: "text", text: "1 " },
		{ tag: "tag_open" },
		{ tag: "text", text: "In" },
		{ tag: "tag_close" },
		{ tag: "text", text: "\n" },
		{ tag: "tag_open" },
		{ tag: "text", text: "the" },
		{ tag: "tag_close" },
		{ tag: "text", text: " 012\n" },
		{ tag: "tag_open" },
		{ tag: "text", text: "beginning" },
		{ tag: "tag_close" },
		{ tag: "text", text: "." },
	]);
});

test("whitespace", () => {
	const s = "\\p  \n  \nasdf\n\n\n";

	expectTokens(s, [
		{ tag: "tag_open" },
		{ tag: "text", text: "\n  \nasdf\n\n\n" },
	]);
});
