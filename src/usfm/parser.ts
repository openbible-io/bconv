// @ts-ignore
import { Tokenizer, type Token } from './tokenizer.ts';
// @ts-ignore
import { type Ast } from '../ast.ts';
// @ts-ignore
import * as Tag from './tag.ts';

export type Document = { ast: Ast, errors: Error[] };
export type Error = {
	token: Token,
	kind: { 'expected_self_close': Token } |
		'Expected attribute value' |
		'Expected verse or chapter number' |
		'Invalid heading level'
	,
};

const whitelist = {
	markers: new Set([
		'c',
		'v',
		'id',
	]),
	inline: new Set([
		'w', // word
		'qs', // selah
		'qac', // acrostic letter mark
		'litl', // list entry total
		'lik', // list entry key
		'liv', // list entry value
		'add', // translator addition
		'k', // keyword
		'nd', // name of deity
		'ord', // ordinal number ending
		'pn', // proper name
		'png', // proper geographic name
		'addpn', // add + pn
		'qt', // quoted text
		'sig', // signature of epistle
		'sls', // secondary language source (like aramaic)
		'tl', // transliterated
		'wj', // words of Jesus
		'em', // emphatic
		'bd', // bold
		'it', // italic
		'bdit', // bold italic
		'no', // normal
		'sc', // small cap
		'sup', // superscript
	]),
};

export class Parser {
	tokenizer: Tokenizer;
	ast: Ast = [];
	errors: Error[] = [];

	constructor(tokenizer: Tokenizer) {
		this.tokenizer = tokenizer;
	}

	appendErr(token: Token, kind: Error['kind']) {
		this.errors.push({ token, kind });
		const msg = typeof kind == 'string' ? kind : Object.keys(kind)[0];
		return Error(msg);
	}

	expect(tag: Token['tag'], why: Error['kind']) {
		const token = this.tokenizer.peek();
		if (token.tag == tag) {
			this.tokenizer.next();
			return token;
		}

		throw this.appendErr(token, why);
	}

	maybeClose(open: Token) {
		const close = this.tokenizer.peek();
		if (close.tag == 'tag_close') {
			const openText = this.tokenizer.view(open);
			const closeText = this.tokenizer.view(close);
			if (openText == closeText.substring(0, closeText.length - 1)) {
				this.tokenizer.next();
				return true;
			}
		}
	}

	expectSelfClose(forToken: Token) {
		const token = this.tokenizer.peek();
		if (token.tag == 'tag_close') {
			this.tokenizer.next();
			if (this.tokenizer.view(token) == "\\*") return;
		}
		throw this.appendErr(token, { expected_self_close: forToken });
	}

	attributes() {
		const token = this.tokenizer.peek();
		if (token.tag != 'attribute_start') return;
		this.tokenizer.next();
		// https://ubsicap.github.io/usfm/attributes/index.html
		while (true) {
			const id = this.tokenizer.peek();
			if (id.tag != 'id') break;
			this.tokenizer.next();

			const n = this.tokenizer.peek();
			if (n.tag == 'kv_sep') {
				this.tokenizer.next();
				this.expect('id', 'Expected attribute value');
			} else {
				// Default attribute depending on the tag.
				// Since we're not a validator, just ignore it.
			}
		}
	}

	text(token: Token) {
		if (token.tag != 'text') return;

		const text = this.tokenizer.view(token);
		this.ast.push({ text });
		return true;
	}

	marker(token: Token, tag?: Tag.Tag) {
		if (!tag || !whitelist.markers.has(tag.tag)) return;

		const maybeText = this.tokenizer.peek();
		if (maybeText.tag == 'text') {
			const text = this.tokenizer.view(maybeText);
			if (tag.tag == 'id') {
				this.tokenizer.next();
				const match = text.match(/^\w+/);
				if (match) this.ast.push({ book: match[0] });
				return true;
			}
			const match = text.match(/^[ \t]*(\d+\s*)/);
			if (match && match[1]) {
				this.tokenizer.pos = maybeText.start + match[1].length;
				const n = parseInt(match[1]);
				if (tag.tag == 'c') {
					this.ast.push({ chapter: n });
				} else {
					this.ast.push({ verse: n });
				}
				return true;
			}
		}
		throw this.appendErr(token, 'Expected verse or chapter number');
	}

	milestone(token: Token, tag?: Tag.Tag) {
		if (!tag || !Tag.isMilestone(tag)) return;

		this.attributes();
		this.expectSelfClose(token);
		return true;
	}

	paragraph(token: Token, tag?: Tag.Tag) {
		if (!tag || !Tag.isParagraph(tag)) return;

		const next = this.tokenizer.peek();
		const text = next.tag =='text' ? this.tokenizer.view(this.tokenizer.next()) : '';

		if (tag.tag == 'b') this.ast.push({ break: 'line' });
		else if (['pm', 'pmo', 'pmr', 'pmc'].includes(tag.tag)) this.ast.push({ break: 'block' });
		else if (tag.tag == 's') {
			if (!text) return; // ignore
			if (tag.n && (tag.n < 0 || tag.n > 4)) throw this.appendErr(token, 'Invalid heading level');
			this.ast.push({ text, tag: `h${tag.n ?? 1}` as 'h1' | 'h2' | 'h3' | 'h4' });
			return true
		} else {
			this.ast.push({ break: 'paragraph' });
		}
		return true;
	}

	character(token: Token, tag?: Tag.Tag) {
		if (!tag || !Tag.isCharacter(tag)) return;

		const maybeText = this.tokenizer.peek();
		const res = this.text(maybeText);
		if (res) this.tokenizer.next();

		// Undocumented but reasonable
		this.maybeClose(token);

		return res;
	}

	// \f ... \f*
	inline(token: Token, tag?: Tag.Tag) {
		if (!tag || !Tag.isInline(tag)) return;

		const whitelisted = whitelist.inline.has(tag.tag);
		const saved = this.ast.length;
		while (['tag_open', 'text'].includes(this.tokenizer.peek().tag)) this.next();
		if (!whitelisted) this.ast.length = saved;

		this.attributes();
		this.maybeClose(token);

		return true;
	}

	next() {
		const token = this.tokenizer.next();
		if (token.tag == 'eof') return 'eof';

		let tag: Tag.Tag | undefined;
		if (token.tag == 'tag_open') tag = Tag.init(this.tokenizer.view(token));

		return this.marker(token, tag) ||
			this.milestone(token, tag) ||
			this.inline(token, tag) ||
			this.paragraph(token, tag) ||
			this.character(token, tag) ||
			this.text(token);
	}

	document(): Document {
		while (true) {
			try { if (this.next() == 'eof') break; } catch {}
		}
		return { ast: this.ast, errors: this.errors };
	}
}
