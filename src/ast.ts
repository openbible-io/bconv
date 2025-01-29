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
export type TextNode = {
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
	book?(book: string): void;
	bookSection?(section: string): void;
	chapter?(n: number): void;
	verse?(n: number): void;
	text?(text: string, attributes?: TextAttributes): void;
	heading?(level: HeadingLevel, text: string): void;
	paragraph?(class_?: string): void;
	break?(class_?: string): void;

	visitNode(n: Node) {
		if (this.book && "book" in n) this.book(n.book);
		else if (this.bookSection && "bookSection" in n) {
			this.bookSection(n.bookSection);
		} else if (this.chapter && "chapter" in n) this.chapter(n.chapter);
		else if (this.verse && "verse" in n) this.verse(n.verse);
		else if (this.heading && "level" in n) this.heading(n.level, n.text);
		else if (this.text && "text" in n) {
			this.text(
				n.text,
				(n as TextNode /* heading check is above */).attributes,
			);
		} else if (this.paragraph && "paragraph" in n) this.paragraph(n.class);
		else if (this.break && "break" in n) this.break(n.break);
	}

	visit(ast: Ast) {
		for (let i = 0; i < ast.length; i++) this.visitNode(ast[i]);
	}
}
