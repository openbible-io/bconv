import { expect, test } from "bun:test";
import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { usfm } from "./src/index.ts";

test("usfm BSB", () => {
	for (const dir of readdirSync("testdata")) {
		if (!dir.endsWith("BSB.usfm")) continue;

		const s = readFileSync(join("testdata", dir), "utf8");
		const parsed = usfm.parse(s);
		expect(parsed.errors).toEqual([]);
	}
});
