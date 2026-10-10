import assert from "node:assert/strict";
import { test } from "node:test";
import { summary } from "./mastodon.mts";

// 가용성/2026년 10월 11일 01시 사고 as baked, whose wikitext went out verbatim
const report = `<div class="mw-parser-output"><div class="av-report">
<div class="av-when"><span class="fw-time" data-time="2026-10-11 01:20">2026-10-11 01:20</span>부터 <span class="fw-time" data-time="2026-10-11 01:27">2026-10-11 01:27</span>까지&#32;(<span class="fw-time-zone">한국 시간</span>) · <a href="../가용성/2026년_10월.html" title="가용성/2026년 10월">그 달의 가용성</a></div>
<p><span class="fw-time" data-time="2026-10-11 01:20">10월 11일 1시 20분</span>부터 <span class="fw-time" data-time="2026-10-11 01:27">1시 27분</span>까지 7분 가까이 페미위키에 들어온 요청의 72%가 빈 500 오류를 받았습니다. 캐시에 없는 문서는 열리지 않았고 편집도 할 수 없었습니다. 새 이미지에서 사라진 상수를 운영 설정이 여전히 쓰고 있어 PHP가 모든 요청에서 멈췄고, 그 두 줄을 지운 설정을 다시 배포해 고쳤습니다. 배포 도구가 망가진 사이트를 성공으로 보고한 까닭은 아직 조사하고 있습니다.
</p>
</div>`;

test("templates in the summary come out as their text", () => {
	assert.equal(
		summary(report),
		"10월 11일 1시 20분부터 1시 27분까지 7분 가까이 페미위키에 들어온 요청의 72%가 빈 500 오류를 받았습니다. 캐시에 없는 문서는 열리지 않았고 편집도 할 수 없었습니다. 새 이미지에서 사라진 상수를 운영 설정이 여전히 쓰고 있어 PHP가 모든 요청에서 멈췄고, 그 두 줄을 지운 설정을 다시 배포해 고쳤습니다. 배포 도구가 망가진 사이트를 성공으로 보고한 까닭은 아직 조사하고 있습니다.",
	);
});

test("links and entities come out as text", () => {
	assert.equal(
		summary(
			'<div class="av-report"><div class="av-when">x</div><p><a href="https://femiwiki.com/" class="external">첫 주소</a>에서 &lt;b&gt;&#32;&amp;</p></div>',
		),
		"첫 주소에서 <b> &",
	);
});

test("a page without a report box has no summary", () => {
	assert.equal(summary("<p>{{사고 목록}}</p>"), undefined);
});

test("markup the build left unrendered stops the post", () => {
	for (const p of [
		"{{시각|2026-10-11 01:20|1시 20분}}부터",
		"[[가용성]]",
		'<a href="틀:없음.html" class="new">틀:없음</a>',
		'<strong class="error">Lua 오류</strong>',
	]) {
		assert.throws(() =>
			summary(
				`<div class="av-report"><div class="av-when">x</div><p>${p}</p></div>`,
			),
		);
	}
});
