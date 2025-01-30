import * as Ast from "../ast.ts";

export class Html extends Ast.Visitor {
	inParagraph = false;

	constructor(
		public write: (s: string) => void,
		public chapterFn: (c: number) => string = (c) => `Chapter ${c}`,
	) {
		super();
	}

	// Allows overriding for interlinear view.
	startParagraph(class_?: string) {
		this.startTag("p", false, class_ ? { class: class_ } : {});
		this.inParagraph = true;
	}

	endParagraph() {
		this.endTag("p");
		this.inParagraph = false;
	}

	startTag(
		tag: string,
		inline: boolean = false,
		attributes?: { [key: string]: string | undefined },
	) {
		if (this.inParagraph && !inline) this.endParagraph();
		this.write(`<${tag}`);
		Object.entries(attributes ?? {}).forEach(([k, v]) => {
			if (v) this.write(` ${k}=\"${v}\"`);
		});
		this.write(`>`);
	}

	endTag(tag: string) {
		this.write(`</${tag}>`);
	}

	override book(book: string, _i: number) {
		this.startTag("h1");
		this.write(book);
		this.endTag("h1");
	}

	override bookSection(section: string, _i: number) {
		this.startTag("h2");
		this.write(section);
		this.endTag("h2");
	}

	override chapter(n: number, _i: number) {
		this.startTag("h2");
		this.write(this.chapterFn(n));
		this.endTag("h2");
	}

	override verse(n: number, _i: number) {
		this.startTag("sup", true);
		this.write(n.toString());
		this.endTag("sup");
	}

	override text(text: string, attributes: Ast.TextAttributes, _i: number) {
		if (!text) return;

		if (Object.keys(attributes).length > 0) {
			this.startTag("span", true, attributes);
			this.write(text);
			this.endTag("span");
		} else {
			this.write(text);
		}
	}

	override heading(level: Ast.HeadingLevel, text: string, _i: number) {
		this.startTag(`h${level}`);
		this.write(text);
		this.endTag(`h${level}`);
	}

	override paragraph(class_: string | undefined, _i: number) {
		this.startParagraph(class_);
	}

	override break(class_: string, _i: number) {
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
		if (this.inParagraph) this.endParagraph();
	}
}
