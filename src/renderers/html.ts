import * as Ast from "../ast.ts";

export class Html extends Ast.Visitor {
	inParagraph = false;

	constructor(
		public write: (s: string) => void,
		public chapterFn: (c: number) => string = (c) => `Chapter ${c}`,
	) {
		super();
	}

	startTag(
		tag: string,
		inline: boolean = false,
		attributes?: { [key: string]: string | undefined },
	) {
		if (this.inParagraph && !inline) {
			this.endTag("p");
			this.inParagraph = false;
		}
		this.write(`<${tag}`);
		Object.entries(attributes ?? {}).forEach(([k, v]) => {
			if (v) this.write(` ${k}=\"${v}\"`);
		});
		this.write(`>`);
	}

	endTag(tag: string) {
		this.write(`</${tag}>`);
	}

	override book(book: string) {
		this.startTag("h1");
		this.write(book);
		this.endTag("h1");
	}

	override bookSection(section: string) {
		this.startTag("h2");
		this.write(section);
		this.endTag("h2");
	}

	override chapter(n: number) {
		this.startTag("h2");
		this.write(this.chapterFn(n));
		this.endTag("h2");
	}

	override verse(n: number) {
		this.startTag("sup", true);
		this.write(n.toString());
		this.endTag("sup");
	}

	override text(text: string, _attributes?: Ast.TextAttributes) {
		this.write(text);
	}

	override heading(level: Ast.HeadingLevel, text: string) {
		this.startTag(`h${level}`);
		this.write(text);
		this.endTag(`h${level}`);
	}

	override paragraph(class_?: string) {
		this.startTag("p", false, { class: class_ });
		this.inParagraph = true;
	}

	override break(class_?: string) {
		if (this.inParagraph) this.startTag("br", true, { class: class_ });
	}

	isInline(node: Ast.Node): boolean {
		return typeof node == "string" || "verse" in node ||
			("text" in node && !("level" in node));
	}

	override visit(ast: Ast.Ast) {
		// We can clean up a bit as we visit.
		for (let i = 0; i < ast.length; i++) {
			let n = ast[i];
			const next = ast[i + 1];
			// Replace trailing space with single whitespace.
			if (typeof n == "string") n = n.replace(/\s+$/, " ");
			// Skip breaks before non-inline elements.
			else if ("break" in n && !this.isInline(next)) continue;
			else if ("text" in n) n.text = n.text.replace(/\s+$/, " ");

			this.visitNode(n, i);
		}
		if (this.inParagraph) {
			this.endTag("p");
			this.inParagraph = false;
		}
	}
}
