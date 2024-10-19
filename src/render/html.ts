import * as Ast from '../ast.ts';

function startTag(
	write: (b: string) => void,
	tag: string,
	attributes?: { [key: string]: string | undefined },
) {
	write(`<${tag}`);
	Object.entries(attributes ?? {}).forEach(([k, v]) => {
		if (v) write(` ${k}=\"${v}\"`);
	});
	write(`>`);
}

function endTag(
	write: (b: string) => void,
	tag: string,
) {
	write(`</${tag}>`);
}

export function html(write: (b: string) => void, ast: Ast.Ast) {
	for (let i = 0; i < ast.length; i++) {
		if ('text' in ast[i]) {
			const t = ast[i] as Ast.TextNode;
			if (t.tag) startTag(write, t.tag, { align: t.align });
			write(t.text);
			if (t.tag) endTag(write, t.tag);
		} else if ('break' in ast[i]) {
			const b = ast[i] as Ast.BreakNode;
			if (b.break == 'line') {
				startTag(write, 'br');
			} else {
				startTag(write, 'p', {
					class: b.break == 'paragraph' ? undefined : b.break,
				});
			}
		} else if ('book' in ast[i]) {
			const b = ast[i] as Ast.BookNode;
			startTag(write, 'h1');
			write(b.book);
			endTag(write, 'h1');
		} else if ('chapter' in ast[i]) {
			const c = ast[i] as Ast.ChapterNode;
			startTag(write, 'h2');
			write(`Chapter ${c.chapter.toString()}`);
			endTag(write, 'h2');
		} else if ('verse' in ast[i]) {
			const v = ast[i] as Ast.VerseNode;
			startTag(write, 'sup');
			if (typeof v.verse == 'number') {
				write(v.verse.toString());
			} else {
				write(`${v.verse.start}-${v.verse.end}`);
			}
			write(' ');
			endTag(write, 'sup');
		}
	}
}
