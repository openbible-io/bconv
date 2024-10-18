import { test } from 'node:test';
import { parse } from './usfm.ts';

test('bsb snippet', t => {
	const parsed = parse(`
\\id GEN - Berean Study Bible
\\h Genesis
\\toc1 Genesis
\\mt1 Genesis
\\c 1
\\s1 The Creation
\\r (John 1:1–5; Hebrews 11:1–3)
\\b
\\m 
\\v 1 In the beginning God created the heavens and the earth. 
\\b
\\m 
\\v 2 Now the earth was formless and void, and darkness was over the surface of the deep. And the Spirit of God was hovering over the surface of the waters. 
\\s2 The First Day
\\b
\\pmo 
\\v 3 And God said, “Let there be light,” \f + \fr 1:3 \ft Cited in 2 Corinthians 4:6\f* and there was light. 
`);

	t.assert.equal(parsed, [
		{ book: 'gen' },
		{ text: 'Genesis', tag: 'h1' },
		{ chapter: 1 },
		{ text: 'The Creation', tag: 'h2' },
		{ break: 'line' },
		{ break: 'p0' },
		{ verse: 1 },
		{ text: 'In the beginning God created the heavens and the earth. ' },
		{ break: 'line' },
		{ break: 'p0' },
		{ verse: 2 },
		{ text: 'Now the earth was formless and void, and darkness was over the surface of the deep. And the Spirit of God was hovering over the surface of the waters. ' },
		{ text: 'The First Day', tag: 'h3' },
		{ break: 'line' },
		{ break: 'block' },
		{ verse: 2 },
		{ text: 'And God said, “Let there be light,”' },
		{ text: ' and there was light. ' },
	]);
});
