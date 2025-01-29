import { expect } from "jsr:@std/expect";
import { usfm } from "./src/index.ts";
import { join } from "node:path";

Deno.test("usfm BSB", () => {
	for (const dir of Deno.readDirSync("testdata")) {
		if (!dir.name.endsWith("BSB.usfm")) continue;

		const s = Deno.readTextFileSync(join("testdata", dir.name));
		const parsed = usfm.parse(s);
		expect(parsed.errors).toEqual([]);
	}
});
