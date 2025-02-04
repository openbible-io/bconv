// Small intersection of USFM and HTML.
export type Ast = Node[];
export type Node = RefNode | HeadingNode | TextNode | ParagraphNode | BreakNode;

export type RefNode = BookNode | BookSectionNode | ChapterNode | VerseNode;
export type BookNode = { book: string };
/** Psalms are divided into 5 books. */
export type BookSectionNode = { bookSection: string };
export type ChapterNode = { chapter: number };
export type VerseNode = { verse: number };

// deno-lint-ignore no-explicit-any
export type TextAttributes = { [key: string]: any };
export type TextNode =
	| string
	| {
			text: string;
			/** Language, parsing, lemma, transliteration, mapping, footnotes, etc. */
			attributes?: TextAttributes;
	  };
export type HeadingLevel = 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8;
export type HeadingNode = {
	level: HeadingLevel;
	text: string;
};
export type ParagraphNode = {
	paragraph: "";
	class?: string;
};
export type BreakNode = {
	break: "";
};

export abstract class Visitor {
	book(_book: string, _i: number): void {}
	bookSection(_section: string, _i: number): void {}
	chapter(_n: number, _i: number): void {}
	verse(_n: number, _i: number): void {}
	text(_text: string, _attributes: TextAttributes, _i: number): void {}
	heading(_level: HeadingLevel, _text: string, _i: number): void {}
	paragraph(_class: string | undefined, _i: number): void {}
	break(_class: string | undefined, _i: number): void {}

	visitNode(n: Node, i: number) {
		if (typeof n == "string") this.text(n, {}, i);
		else if ("book" in n) this.book(n.book, i);
		else if ("bookSection" in n) this.bookSection(n.bookSection, i);
		else if ("chapter" in n) this.chapter(n.chapter, i);
		else if ("verse" in n) this.verse(n.verse, i);
		else if ("level" in n) this.heading(n.level, n.text, i);
		else if ("text" in n) this.text(n.text, n.attributes ?? {}, i);
		else if ("paragraph" in n) this.paragraph(n.class, i);
		else if ("break" in n) this.break(n.break, i);
	}

	visit(ast: Ast) {
		for (let i = 0; i < ast.length; i++) this.visitNode(ast[i], i);
	}
}
