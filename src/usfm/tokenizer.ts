export type Token = {
	tag:
		| "tag_open"
		| "tag_close"
		| "text"
		| "attribute_start"
		| "id"
		| "kv_sep"
		| "eof";
	start: number;
	end: number;
};

// TODO: refactor to regexes for code size
export class Tokenizer {
	buffer: string;
	pos = 0;
	in_attribute = false;
	static whitespace = [" ", "\t", "\r", "\n"];

	constructor(buffer: string) {
		this.buffer = buffer;
	}

	private readByte() {
		if (this.pos >= this.buffer.length) return;
		const res = this.buffer[this.pos];
		this.pos += 1;
		return res;
	}

	private readUntilDelimiters(delimiters: string[]): number {
		let len = 0;
		while (true) {
			const byte = this.readByte();
			len += 1;
			if (!byte) return len;
			for (let i = 0; i < delimiters.length; i++) {
				if (byte === delimiters[i]) {
					if (byte === "*") {
						// Consume * for ending tags
						len += 1;
					} else {
						this.pos -= 1;
					}
					return len;
				}
			}
		}
	}

	private eatSpaceN(n: number) {
		let n_eaten = 0;
		while (n_eaten <= n) {
			const byte = this.readByte();
			if (!byte) return;
			if (Tokenizer.whitespace.includes(byte)) {
				n_eaten += 1;
			} else {
				this.pos -= 1;
				return;
			}
		}
	}

	eatSpace() {
		this.eatSpaceN(256);
	}

	next(): Token {
		const res: Token = {
			start: this.pos,
			end: this.pos + 1,
			tag: "eof",
		};

		const next_c = this.readByte();
		if (!next_c) {
			res.end = this.pos;
			return res;
		}
		if (next_c === "\\") {
			this.in_attribute = false;
			this.readUntilDelimiters(Tokenizer.whitespace.concat("*", "\\", "|"));
			if (this.buffer[this.pos - 1] !== "*") {
				res.end = this.pos;
				res.tag = "tag_open";
				this.eatSpaceN(1);
			} else {
				// End tag like `\w*` or '\*';
				res.end = this.pos;
				res.tag = "tag_close";
			}
		} else if (next_c === "|") {
			this.in_attribute = true;
			res.tag = "attribute_start";
			this.eatSpace();
		} else if (this.in_attribute) {
			if (next_c === "=") {
				res.tag = "kv_sep";
				this.eatSpace();
				return res;
			}
			if (next_c === '"') {
				let last_backslash = false;
				while (true) {
					const c = this.readByte();
					if (!c) break;
					if (c === '"' && !last_backslash) {
						res.start += 1;
						res.end = this.pos - 1;
						res.tag = "id";
						break;
					}
					last_backslash = c === "\\";
				}
				this.eatSpace();
			} else {
				this.readUntilDelimiters(Tokenizer.whitespace.concat("=", "\\"));
				res.end = this.pos;
				res.tag = "id";
				this.eatSpace();
			}
		} else {
			this.in_attribute = false;
			this.readUntilDelimiters(["|", "\\"]);
			res.end = this.pos;
			res.tag = "text";
		}

		return res;
	}

	peek(): Token {
		const pos = this.pos;
		const res = this.next();
		this.pos = pos;
		return res;
	}

	view(token: Token): string {
		return this.buffer.substring(token.start, token.end);
	}
}
