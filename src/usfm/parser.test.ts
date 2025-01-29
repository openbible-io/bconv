import { expect } from "jsr:@std/expect";
import { parse } from "./index.ts";
import type { Ast } from "../ast.ts";

function expectElements(
	s: string,
	expected: Ast,
	expectedErrors: Error[] = [],
) {
	const parsed = parse(s);
	expect(parsed.errors).toEqual(expectedErrors);
	expect(parsed.ast).toEqual(expected);
}

Deno.test("whitespace", () => {
	expectElements("\\p  \n  \nasdf\n\n\n", [
		{ paragraph: "" },
		{ text: "\n  \nasdf\n\n\n" },
	]);
});

Deno.test("single attribute tag", () => {
	expectElements('\\v 1\\qs Selah |   x-occurences  =   "1" \\qs*', [
		{ verse: 1 },
		{ text: "Selah " },
	]);
});

Deno.test("empty attribute tag", () => {
	expectElements("\\v 1\\w hello|\\w*", [
		{ verse: 1 },
		{ text: "hello" },
	]);
});

Deno.test("milestones", () => {
	expectElements("\\zaln-s\\*\\w In \\w*side\\zaln-e\\* there", [
		{ text: "In " },
		{ text: "side" },
		{ text: " there" },
	]);
});

Deno.test("footnote with inline fqa", () => {
	expectElements("Hello\\f +\\ft footnote:   \\fqa some text\\fqa*.\\f*", [
		{ text: "Hello" },
	]);
});

Deno.test("footnote with block fqa", () => {
	expectElements("\\f +\\fq a\\ft b\\fqa c\\ft d\\f*", []);
});

Deno.test("paragraphs", () => {
	const s = `\\c 1
\\p
\\v 1 verse1
\\p
\\v 2 verse2
`;
	expectElements(s, [
		{ chapter: 1 },
		{ paragraph: "" },
		{ verse: 1 },
		{ text: "verse1\n" },
		{ paragraph: "" },
		{ verse: 2 },
		{ text: "verse2\n" },
	]);
});
