import type * as Ast from '../ast.ts';

export class Html {
	inParagraph = false;
	constructor(public write: (s: string) => void) {}

	startTag(
		tag: string,
		attributes?: { [key: string]: string | undefined },
	) {
		if (tag == 'p') this.inParagraph = true;
		this.write(`<${tag}`);
		Object.entries(attributes ?? {}).forEach(([k, v]) => {
			if (v) this.write(` ${k}=\"${v}\"`);
		});
		this.write(`>`);
	}

	endTag(tag: string) {
		if (tag == 'p') this.inParagraph = false;
		this.write(`</${tag}>`);
	}

	render(ast: Ast.Ast) {
		for (let i = 0; i < ast.length; i++) {
			if ('text' in ast[i]) {
				const t = ast[i] as Ast.TextNode;
				if (t.text) {
					if (t.tag) this.startTag(t.tag, { align: t.align });
					this.write(t.text);
					if (t.tag) this.endTag(t.tag);
				}
			} else if ('break' in ast[i]) {
				const b = ast[i] as Ast.BreakNode;
				if (b.break == 'line') {
					this.startTag('br');
				} else {
					this.startTag('p', {
						class: b.break == 'paragraph' ? undefined : b.break,
					});
				}
			} else if ('chapter' in ast[i]) {
				const c = ast[i] as Ast.ChapterNode;
				this.startTag('h2');
				this.write(`Chapter ${c.chapter.toString()}`);
				this.endTag('h2');
			} else if ('verse' in ast[i]) {
				const v = ast[i] as Ast.VerseNode;
				this.startTag('sup');
				if (typeof v.verse == 'number') {
					this.write(v.verse.toString());
				} else {
					this.write(`${v.verse.start}-${v.verse.end}`);
				}
				this.endTag('sup');
			}
		}
		if (this.inParagraph) this.endTag('p');
	}
}
