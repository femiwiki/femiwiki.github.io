// Adds a closed month's Google Analytics totals to the GA record's tabular data page once.
import type * as Core from "@actions/core";

const TITLE = "Data:페미위키 구글 애널리틱스 기록.tab";

// The columns after the month, in the page's order. GA4's totalUsers is what
// Universal Analytics called users. Most raw sessions are bots, so engaged
// sessions get their own column, which the Universal Analytics months leave empty.
const METRICS = ["totalUsers", "newUsers", "sessions", "engagedSessions"];

type Row = [string, ...(number | null)[]];
type Tab = { data: Row[] };

// The month before the one `now` falls in, as YYYY-MM
export function previousMonth(now: Date): string {
	const d = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - 1, 1));
	return d.toISOString().slice(0, 7);
}

export function lastDay(month: string): string {
	const [year, m] = month.split("-").map(Number);
	return new Date(Date.UTC(year, m, 0)).toISOString().slice(0, 10);
}

// The row goes in month order, so a backfilled month lands where it belongs
export function insert<T extends Tab>(tab: T, added: Row): T | undefined {
	if (tab.data.some(([month]) => month === added[0])) return undefined;
	const at = tab.data.findIndex(([month]) => month > added[0]);
	const data = [...tab.data];
	data.splice(at < 0 ? data.length : at, 0, added);
	return { ...tab, data };
}

// The wiki's API with the login cookies kept between calls
function wiki(api: string) {
	const cookies = new Map<string, string>();
	return async (params: Record<string, string>) => {
		const response = await fetch(api, {
			method: "POST",
			headers: {
				Cookie: [...cookies].map(([k, v]) => `${k}=${v}`).join("; "),
			},
			body: new URLSearchParams({
				format: "json",
				formatversion: "2",
				...params,
			}),
		});
		for (const c of response.headers.getSetCookie()) {
			const [pair] = c.split(";");
			const eq = pair.indexOf("=");
			cookies.set(pair.slice(0, eq), pair.slice(eq + 1));
		}
		if (!response.ok) throw new Error(`${params.action}: ${response.status}`);
		const body = await response.json();
		if (body.error) throw new Error(`${params.action}: ${body.error.info}`);
		return body;
	};
}

export default async ({
	core,
	env: {
		MONTH,
		GA_ACCESS_TOKEN,
		GA_PROPERTY,
		WIKI_BOT_USER,
		WIKI_BOT_PASSWORD,
		WIKI_API = "https://femiwiki.com/api.php",
	},
}: {
	core: typeof Core;
	env: NodeJS.ProcessEnv;
}) => {
	if (
		!GA_ACCESS_TOKEN ||
		!GA_PROPERTY ||
		!WIKI_BOT_USER ||
		!WIKI_BOT_PASSWORD
	) {
		core.info("No Google token or wiki bot login, nothing to record.");
		return;
	}
	const month = MONTH || previousMonth(new Date());
	if (!/^\d{4}-(0[1-9]|1[0-2])$/.test(month))
		throw new Error(`month must be YYYY-MM, got '${month}'`);

	const report = await fetch(
		`https://analyticsdata.googleapis.com/v1beta/properties/${GA_PROPERTY}:runReport`,
		{
			method: "POST",
			headers: {
				Authorization: `Bearer ${GA_ACCESS_TOKEN}`,
				"Content-Type": "application/json",
			},
			body: JSON.stringify({
				dateRanges: [{ startDate: `${month}-01`, endDate: lastDay(month) }],
				metrics: METRICS.map((name) => ({ name })),
			}),
		},
	);
	if (!report.ok)
		throw new Error(`runReport: ${report.status} ${await report.text()}`);
	const values = (await report.json()).rows?.[0]?.metricValues?.map(
		(v: { value: string }) => Number(v.value),
	);
	if (!values) throw new Error(`no data for ${month}`);

	const api = wiki(WIKI_API);
	const { logintoken } = (
		await api({ action: "query", meta: "tokens", type: "login" })
	).query.tokens;
	const login = await api({
		action: "login",
		lgname: WIKI_BOT_USER,
		lgpassword: WIKI_BOT_PASSWORD,
		lgtoken: logintoken,
	});
	if (login.login.result !== "Success")
		throw new Error(`login: ${login.login.result}`);

	const page = (
		await api({
			action: "query",
			prop: "revisions",
			rvprop: "content|timestamp",
			rvslots: "main",
			titles: TITLE,
		})
	).query.pages[0].revisions[0];
	const tab = insert(JSON.parse(page.slots.main.content), [month, ...values]);
	if (tab === undefined) {
		core.info(`${TITLE} already has ${month}.`);
		return;
	}

	const { csrftoken } = (await api({ action: "query", meta: "tokens" })).query
		.tokens;
	const edit = await api({
		action: "edit",
		title: TITLE,
		text: JSON.stringify(tab),
		summary: `${month} 구글 애널리틱스 기록 (femiwiki.github.io 수집 작업)`,
		bot: "1",
		basetimestamp: page.timestamp,
		token: csrftoken,
	});
	if (edit.edit.result !== "Success")
		throw new Error(`edit: ${JSON.stringify(edit.edit)}`);
	core.info(`${TITLE}: ${month}`);
};
