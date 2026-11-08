import assert from "node:assert/strict";
import { test } from "node:test";
import { insert, lastDay, previousMonth } from "./ga-record.mts";

// What the data page keeps besides its rows stays as it was
const tab = {
	license: "CC0-1.0",
	data: [
		["2016-12", 583, 473, 693, null],
		["2018-04", 1, 2, 3, null],
	] as [string, ...(number | null)[]][],
};

test("the previous month crosses the year", () => {
	assert.equal(previousMonth(new Date("2026-01-02T01:00:00Z")), "2025-12");
	assert.equal(previousMonth(new Date("2026-11-02T01:00:00Z")), "2026-10");
});

test("the last day knows February", () => {
	assert.equal(lastDay("2024-02"), "2024-02-29");
	assert.equal(lastDay("2026-10"), "2026-10-31");
});

test("a new month goes at the end", () => {
	const after = insert(tab, ["2026-10", 4, 5, 6, 7]);
	assert.equal(after?.license, "CC0-1.0");
	assert.deepEqual(after?.data.at(-1), ["2026-10", 4, 5, 6, 7]);
	assert.equal(tab.data.length, 2);
});

test("a backfilled month lands in order", () => {
	assert.deepEqual(
		insert(tab, ["2017-06", 4, 5, 6, 7])?.data.map(([m]) => m),
		["2016-12", "2017-06", "2018-04"],
	);
	assert.equal(insert(tab, ["2016-11", 1, 1, 1, 1])?.data[0][0], "2016-11");
});

test("a month already there is left alone", () => {
	assert.equal(insert(tab, ["2016-12", 1, 1, 1, 1]), undefined);
});
