import type * as Ast from '../ast.ts';

function startTag(
	tag: string,
	write: (b: string) => void,
	attributes?: { [key: string]: string | undefined },
) {
	write(`<${tag}`);
	Object.entries(attributes ?? {}).forEach(([k, v]) => {
		if (v) write(` ${k}=\"${v}\"`);
	});
	write(`>`);
}

function endTag(
	tag: string,
	write: (b: string) => void,
) {
	write(`</${tag}>`);
}

export function html(ast: Ast.Ast, write: (b: string) => void) {
	for (let i = 0; i < ast.length; i++) {
		if ('text' in ast[i]) {
			const t = ast[i] as Ast.TextNode;
			if (t.tag) startTag(t.tag, write, { align: t.align });
			write(t.text);
			if (t.tag) endTag(t.tag, write);
		} else if ('break' in ast[i]) {
			const b = ast[i] as Ast.BreakNode;
			if (b.break == 'line') {
				startTag('br', write);
			} else {
				startTag('p', write, {
					class: b.break == 'paragraph' ? undefined : b.break,
				});
			}
		} else if ('chapter' in ast[i]) {
			const c = ast[i] as Ast.ChapterNode;
			startTag('h2', write);
			write(`Chapter ${c.chapter.toString()}`);
			endTag('h2', write);
		} else if ('verse' in ast[i]) {
			const v = ast[i] as Ast.VerseNode;
			startTag('sup', write);
			if (typeof v.verse == 'number') {
				write(v.verse.toString());
			} else {
				write(`${v.verse.start}-${v.verse.end}`);
			}
			endTag('sup', write);
		}
	}
}
