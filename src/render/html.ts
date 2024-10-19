// @ts-ignore
import * as Ast from '../ast.ts';

function startTag(tag: string, attributes?: { [key: string]: string | undefined }) {
	process.stdout.write(`<${tag}`);
	Object.entries(attributes ?? {}).forEach(([k, v]) => {
		if (v) process.stdout.write(` ${k}=\"${v}\"`);
	});
	process.stdout.write(`>`);
}

function endTag(tag: string) {
	process.stdout.write(`</${tag}>`);
}

export function html(ast: Ast.Ast) {
	for (let i = 0; i < ast.length; i++) {
		if ('text' in ast[i]) {
			const t = ast[i] as Ast.TextNode;
			if (t.tag) startTag(t.tag, { align: t.align });
			process.stdout.write(t.text);
			if (t.tag) endTag(t.tag);
		} else if ('break' in ast[i]) {
			const b = ast[i] as Ast.BreakNode;
			if (b.break == 'line') {
				startTag('br');
			} else {
				startTag('p', { class: b.break == 'paragraph' ? undefined : b.break });
			}
		} else if ('book' in ast[i]) {
			const b = ast[i] as Ast.BookNode;
			startTag('h1');
			process.stdout.write(b.book);
			endTag('h1');
		} else if ('chapter' in ast[i]) {
			const c = ast[i] as Ast.ChapterNode;
			startTag('h2');
			process.stdout.write(`Chapter ${c.chapter.toString()}`);
			endTag('h2');
		} else if ('verse' in ast[i]) {
			const v = ast[i] as Ast.VerseNode;
			startTag('sup');
			if (typeof v.verse == 'number') {
				process.stdout.write(v.verse.toString());
			} else {
				process.stdout.write(`${v.verse.start}-${v.verse.end}`);
			}
			process.stdout.write(' ');
			endTag('sup');
		}
	}
}
