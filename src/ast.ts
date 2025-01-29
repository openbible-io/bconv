// Small intersection of USFM and HTML.
export type Ast = Node[];
export type Node = RefNode | HeadingNode | TextNode | ParagraphNode | BreakNode;

export type RefNode = BookNode | BookSectionNode | ChapterNode | VerseNode;
export type BookNode = { book: string };
/** Psalms are divided into 5 books. */
export type BookSectionNode = { bookSection: string };
export type ChapterNode = { chapter: number };
export type VerseNode = { verse: number };

export type TextAttributes = { [key: string]: string };
export type TextNode = string | {
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
	book(_book: string): void {}
	bookSection(_section: string): void {}
	chapter(_n: number): void {}
	verse(_n: number): void {}
	text(_text: string, _attributes?: TextAttributes): void {}
	heading(_level: HeadingLevel, _text: string): void {}
	paragraph(_class?: string): void {}
	break(_class?: string): void {}

	visitNode(n: Node) {
		if (typeof n == "string") this.text(n);
		else if ("book" in n) this.book(n.book);
		else if ("bookSection" in n) this.bookSection(n.bookSection);
		else if ("chapter" in n) this.chapter(n.chapter);
		else if ("verse" in n) this.verse(n.verse);
		else if ("level" in n) this.heading(n.level, n.text);
		else if ("text" in n) this.text(n.text, n.attributes);
		else if ("paragraph" in n) this.paragraph(n.class);
		else if ("break" in n) this.break(n.break);
	}

	visit(ast: Ast) {
		for (let i = 0; i < ast.length; i++) this.visitNode(ast[i]);
	}
}
