// Used to have a nice list, but no one follows the standard!
export type Tag = { tag: string; n?: number };

export function init(s: string): Tag {
	const match = s.match(/^\\([^0-9]*)([0-9]+)?(-e|-s|\*)?$/);
	if (!match) throw Error("Invalid tag: " + s);

	const res: Tag = { tag: match[1] + (match[3] ?? "") };
	if (match[2]) res.n = parseInt(match[2]);
	return res;
}

const paragraphs = new Set([
	// identification
	"id",
	"usfm",
	"ide",
	"sts",
	"rem",
	"h",
	"toc",
	"toca",
	// introductions
	"imt",
	"is",
	"ip",
	"ipi",
	"im",
	"imi",
	"ipq",
	"imq",
	"ipr",
	"iq",
	"ib",
	"ili",
	"iot",
	"io",
	"iex",
	"imte",
	"ie",
	// titles | headings, and labels
	"mt",
	"mte",
	"ms",
	"mr",
	"s",
	"sr",
	"r",
	"d",
	"sp",
	"sd",
	// chapters and verses
	"c",
	"cl",
	"cp",
	"cd",
	// parapgraphs
	"p",
	"m",
	"po",
	"pr",
	"cls",
	"pmo",
	"pm",
	"pmc",
	"pmr",
	"pi",
	"mi",
	"nb",
	"pc",
	"ph",
	"b",
	// poetry
	"q",
	"qr",
	"qc",
	"qa",
	"qm",
	"qd",
	// lists
	"lh",
	"li",
	"lf",
	"lim",
	// tables
	"tr",
	// cross references
	"x",
	// spacing and breaks
	"pb",
	// special features
	"fig",
]);

const inlines = new Set([
	// introductions
	"ior",
	"iqt",
	// chapters and verses
	"ca",
	"va",
	"vp",
	// poetry
	"qs",
	"qac",
	// lists
	"litl",
	"lik",
	"liv",
	// footnotes
	"f",
	"fe",
	"fv",
	"fdc",
	"fm",
	// cross references
	"x",
	"xop",
	"xot",
	"xnt",
	"xdc",
	"rq",
	// words and characters
	"add",
	"bk",
	"dc",
	"k",
	"nd",
	"ord",
	"pn",
	"png",
	"addpn",
	"qt",
	"sig",
	"sls",
	"tl",
	"wj",
	// character styling
	"em",
	"bd",
	"it",
	"bdit",
	"no",
	"sc",
	"sup",
	// special features
	"fig",
	"ndx",
	"rb",
	"pro",
	"w",
	"wg",
	"wh",
	"wa",
	// linking
	"jmp",
	// extended study content
	"ef",
	"ex",
	"cat",
]);

const headings = new Set([
	"h",
	"mt",
	"mte",
	"toc",
	"ms",
	"mr",
	"s",
	"sr",
	"r",
	"d",
	"sp",
	"sd",
]);

export function isParagraph(t: Tag) {
	return paragraphs.has(t.tag);
}

export function isInline(t: Tag) {
	return inlines.has(t.tag);
}

export function isMilestoneStart(t: Tag) {
	return t.tag.includes("-s");
}

export function isMilestoneEnd(t: Tag) {
	return t.tag.endsWith("-e");
}

export function isMilestone(t: Tag) {
	return isMilestoneStart(t) || isMilestoneEnd(t);
}

export function isCharacter(t: Tag) {
	return !isMilestone(t) && !isParagraph(t);
}

export function isHeading(t: Tag) {
	return headings.has(t.tag);
}

export function isClose(t: Tag) {
	return t.tag.endsWith("*");
}

export function validAttributes(t: Tag): string[] {
	return {
		w: ["lemma", "strong", "srcloc"],
		rb: ["gloss"],
		xt: ["link-href"],
		fig: ["alt", "src", "size", "loc", "copy", "ref"],
	}[t.tag] || [];
}

export function defaultAttribute(t: Tag) {
	return {
		w: "lemma",
		rb: "gloss",
		xt: "link-href",
	}[t.tag];
}
