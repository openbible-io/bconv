//! - The AST is modeled after the text formatting of the original
//! [Hebrew](https://izbicki.me/blog/ancient-hebrew-torah-scrolls.html) and
//! [Greek](https://duckduckgo.com/?q=ancient+greek+biblical+manuscripts&iar=images) manuscripts.
//! - There is no nesting allowed.
//! - `RefNode` has been added to accomodate versification.
//!
//! This purposefully loses footnotes, x-refs, and other elements found in modern translations.
//! Why?
//! 1. These are uninspired words that the reader usually doesn't care about.
//! 2. The format requires a complex nested structure.

export type Ast = Node[];
export type Node = TextNode | BreakNode | RefNode;
export type TextNode = {
	text: string;
	tag?: 'h1' | 'h2' | 'h3' | 'h4';
	align?: 'left' | 'center' | 'right';
};
export type BreakNode = {
	break: 'paragraph' | 'block' | 'line';
};

export type RefNode = BookNode | SectionNode | ChapterNode | VerseNode;
/** Manuscripts may lack page breaks between books. */
export type BookNode = { book: string };
/** Psalms are divided into 5 books. */
export type SectionNode = { section: number };
/** No children because chapters/verses cannot nest. */
export type ChapterNode = { chapter: number };
export type VerseNode = {
	verse: number | {
		start: number;
		/** Paraphrase translations may include verse ranges */
		end: number;
	};
};

function canonicalizeText(node: TextNode) {
	node.text = isSimpleText(node)
		? node.text.replace(/\s+/g, ' ')
		: node.text.trim();
}

function isSimpleText(n?: Node) {
	const keys = Object.keys(n ?? {});
	return keys.length == 1 && keys[0] == 'text';
}

// Modifies Ast in-place, returning a new one.
export function canonicalize(ast: Ast): Ast {
	const tmp = ast as (Node | undefined)[];
	let inBook = false;
	for (let i = 0; i < tmp.length; i++) {
		if ('book' in ast[i]) inBook = true;
		if (!inBook && !('book' in ast[i])) {
			tmp[i] = undefined;
			continue;
		}

		if ('text' in ast[i]) {
			const t = tmp[i] as TextNode;
			// carry forward
			if (isSimpleText(tmp[i]) && isSimpleText(tmp[i - 1])) {
				const t2 = tmp[i - 1] as TextNode;
				t.text = t2.text + t.text;
				tmp[i - 1] = undefined;
			}
			canonicalizeText(t);
			if (t.text.trim() == '') tmp[i] = undefined;
		} else if ('break' in ast[i]) {
			if (tmp[i - 1]) {
				if ('tag' in ast[i - 1]) tmp[i] = undefined;
				if ('break' in ast[i - 1]) tmp[i - 1] = undefined;
			}
		}
	}

	for (let i = tmp.length - 1; i > 0; i--) {
		const el = tmp[i];
		if (el && 'break' in el) tmp[i] = undefined;
		else break;
	}

	return ast.filter(Boolean) as Node[];
}
