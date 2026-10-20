import assert from "node:assert/strict";
import { test } from "node:test";
import { insert, lastDay, previousMonth, row } from "./ga-record.mts";

// The head of 페미위키:구글 애널리틱스 기록 as it stood in 2026
const page = `{| class="wikitable sortable"
!'''ga:date (날짜)'''
!'''ga:users (방문자)'''
!'''ga:newUsers (신규방문자)'''
!'''ga:sessions (세션, 활동적 사용)'''
|-
|2017-01-01
|583
|473
|693
|-
|2018-05-01
|1
|2
|3
|}

== 2017년의 요약 ==`;

test("the previous month crosses the year", () => {
	assert.equal(previousMonth(new Date("2026-01-02T01:00:00Z")), "2025-12");
	assert.equal(previousMonth(new Date("2026-11-02T01:00:00Z")), "2026-10");
});

test("the last day knows February", () => {
	assert.equal(lastDay("2024-02"), "2024-02-29");
	assert.equal(lastDay("2026-10"), "2026-10-31");
});

test("a new month goes at the end, and the header gains a column once", () => {
	const text = insert(page, "2026-10", row("2026-10", ["4", "5", "6", "7"]));
	assert.ok(text);
	assert.match(
		text,
		/!'''ga:sessions \(세션, 활동적 사용\)'''\n!'''engagedSessions \(참여 세션\)'''\n\|-\n\|2017-01-01/,
	);
	assert.match(text, /\|3\n\|-\n\|2026-10-01\n\|4\n\|5\n\|6\n\|7\n\|\}\n/);
	const again = insert(text, "2026-11", row("2026-11", ["1", "1", "1", "1"]));
	assert.equal(again?.match(/engagedSessions/g)?.length, 1);
});

test("a backfilled month lands in order", () => {
	const text = insert(page, "2017-06", row("2017-06", ["4", "5", "6", "7"]));
	assert.match(
		text ?? "",
		/\|693\n\|-\n\|2017-06-01\n\|4\n\|5\n\|6\n\|7\n\|-\n\|2018-05-01/,
	);
	const start = insert(page, "2016-12", row("2016-12", ["1", "1", "1", "1"]));
	assert.match(
		start ?? "",
		/'''\n\|-\n\|2016-12-01\n\|1\n\|1\n\|1\n\|1\n\|-\n\|2017-01-01/,
	);
});

test("a month already there is left alone", () => {
	assert.equal(
		insert(page, "2017-01", row("2017-01", ["1", "1", "1", "1"])),
		undefined,
	);
});
