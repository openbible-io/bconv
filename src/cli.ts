import { stdout } from "node:process";
import { program } from "commander";
import type { Ast } from "./ast.ts";
import * as lib from "./index.ts";
import { extname } from "node:path";

program
	.description("render Bible file to HTML")
	.argument("<string>", "filename")
	.option("-a, --ast", "output ast instead of HTML")
	.action((fname, options) => {
		let ast: Ast;
		const ext = extname(fname.toLowerCase());
		if ([".usfm", ".sfm"].includes(ext)) {
			const file = Deno.readTextFileSync(fname);
			ast = lib.usfm.parseAndPrintErrors(file);
		} else {
			throw Error("unknown file type: " + fname);
		}
		if (options.ast) {
			for (let i = 0; i < ast.length; i++) console.log(JSON.stringify(ast[i]));
		} else {
			const renderer = new lib.renderers.Html((s) => stdout.write(s));
			renderer.visit(ast);
		}
	});

program.parse();
