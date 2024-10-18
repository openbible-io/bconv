import { test, type TestContext } from 'node:test';
import { parse } from './index.ts';
import { type Ast } from '../ast.ts';

function expectElements(t: TestContext, s: string, expected: Ast, expectedErrors: Error[] = []) {
	const parsed = parse(s);
	t.assert.deepEqual(parsed.errors, expectedErrors);
	t.assert.deepEqual(parsed.ast, expected);
}

test('whitespace', t => {
	expectElements(t, '\\p  \n  \nasdf\n\n\n', [
		{ break: 'paragraph' },
		{ text: '\n  \nasdf\n\n\n' },
	]);
});

test('single attribute tag', t => {
	expectElements(t, '\\v 1\\qs Selah |   x-occurences  =   "1" \\qs*', [
		{ verse: 1 },
		{ text: 'Selah '},
	]);
});

test('empty attribute tag', t => {
	expectElements(t, '\\v 1\\w hello|\\w*', [
		{ verse: 1 },
		{ text: 'hello' },
	]);
});

test('milestones', t => {
	expectElements(t, '\\zaln-s\\*\\w In \\w*side\\zaln-e\\* there', [
		{ text: 'In ' },
		{ text: 'side' },
		{ text: ' there' },
	]);
});

test('footnote with inline fqa', t => {
	expectElements(t, 'Hello\\f +\\ft footnote:   \\fqa some text\\fqa*.\\f*', [
		{ text: 'Hello' }
	]);
});

test('footnote with block fqa', t => {
	expectElements(t, '\\f +\\fq a\\ft b\\fqa c\\ft d\\f*', []);
});

test('paragraphs', t => {
	const s = `\\c 1
\\p
\\v 1 verse1
\\p
\\v 2 verse2
`;
	expectElements(t, s, [
		{ chapter: 1 },
		{ break: 'paragraph' },
		{ verse: 1 },
		{ text: 'verse1\n' },
		{ break: 'paragraph' },
		{ verse: 2 },
		{ text: 'verse2\n' },
	]);
});
