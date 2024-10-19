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
	text: string,
	tag?: 'h1' | 'h2' | 'h3' | 'h4',
	align?: 'left' | 'center' | 'right',
};
export type BreakNode = {
	break: 'paragraph' | 'block' | 'line',
};

export type RefNode = BookNode | ChapterNode | VerseNode;
/**
 * Psalms are divided into 5 books.
 * Manuscripts may lack page breaks between books.
 */
export type BookNode = { book: string };
/** No children because chapters/verses cannot nest. */
export type ChapterNode = { chapter: number };
export type VerseNode = { verse: number | {
	start: number,
	/** Paraphrase translations may include verse ranges */
	end: number
} };

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
	let inChapter = false;
	for (let i = 0; i < ast.length; i++) {
		if ('chapter' in ast[i]) inChapter = true;
		if (!inChapter && !('book' in ast[i])) {
			(ast[i] as any) = undefined;
			continue;
		}

		if ('text' in ast[i]) {
			const t = ast[i] as TextNode;
			// carry forward
			if (isSimpleText(ast[i]) && isSimpleText(ast[i - 1])) {
				const t2 = ast[i - 1] as TextNode;
				t.text = t2.text + t.text;
				(ast[i - 1] as any) = undefined;
			}
			canonicalizeText(t);
			if (t.text.trim() == '') (ast[i] as any) = undefined;
		} else if ('break' in ast[i]) {
			if (ast[i - 1]) {
				if ('tag' in ast[i - 1]) (ast[i] as any) = undefined;
				if ('break' in ast[i - 1]) (ast[i - 1] as any) = undefined;
			}
		}
	}

	for (let i = ast.length - 1; i > 0; i--) {
		if (ast[i] && 'break' in ast[i]) (ast[i] as any) = undefined;
		else break;
	}

	return ast.filter(Boolean) as Node[];
}
