import { expect, test } from "bun:test";
import * as Tag from "./tag.ts";

test("tag init", () => {
	expect(Tag.init("\\v")).toEqual({ tag: "v" });
	expect(Tag.init("\\toc3")).toEqual({ tag: "toc", n: 3 });
	expect(Tag.init("\\ts-s")).toEqual({ tag: "ts-s" });
	expect(Tag.init("\\qt-s")).toEqual({ tag: "qt-s" });
	expect(Tag.init("\\qt4-s")).toEqual({ tag: "qt-s", n: 4 });
	expect(Tag.init("\\zaln-s")).toEqual({ tag: "zaln-s" });
});
