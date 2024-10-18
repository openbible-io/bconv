import { test } from 'node:test';
import * as Tag from './tag.ts';

test("tag init", t => {
	const t1 = Tag.init("\\v");
	t.assert.deepEqual({ tag: 'v' }, t1);

	const t2 = Tag.init("\\toc3");
	t.assert.deepEqual({ tag: 'toc', n: 3 }, t2);

	const t3 = Tag.init("\\ts-s");
	t.assert.deepEqual({ tag: "ts-s" }, t3);

	const t4 = Tag.init("\\qt-s");
	t.assert.deepEqual({ tag: "qt-s" }, t4);

	const t5 = Tag.init("\\qt4-s");
	t.assert.deepEqual({ tag: "qt-s", n: 4 }, t5);

	const t6 = Tag.init("\\zaln-s");
	t.assert.deepEqual({ tag: "zaln-s" }, t6);
});
