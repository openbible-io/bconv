import { expect, test } from "bun:test";
import { usfm } from "./src/index.ts";
import { join } from "node:path";
import { readdirSync, readFileSync } from 'node:fs';

test("usfm BSB", () => {
	for (const dir of readdirSync("testdata")) {
		if (!dir.endsWith("BSB.usfm")) continue;

		const s = readFileSync(join("testdata", dir), 'utf8');
		const parsed = usfm.parse(s);
		expect(parsed.errors).toEqual([]);
	}
});
