// Posts each incident report to the wiki's Mastodon status account once.
// The list of reports already posted lives on the data branch, so a report is
// posted after the Deploy that published it, whichever run that was.
import { readdirSync, readFileSync, writeFileSync } from "node:fs";
import type * as Core from "@actions/core";

// Mastodon's limit. A link counts as 23 characters whatever its length.
const LIMIT = 500;
const LINK = 23;

export function summary(wikitext: string): string | undefined {
	const block = wikitext.match(/\{\{사고 보고서([\s\S]*?)\n\}\}/)?.[1];
	const text = block?.match(/\n\|\s*요약\s*=\s*([\s\S]*?)(?=\n\||$)/)?.[1];
	if (text === undefined) return undefined;
	return text
		.replace(/\[\[(?:[^\]|]*\|)?([^\]]*)\]\]/g, "$1")
		.replace(/\[https?:\/\/\S+ ([^\]]*)\]/g, "$1")
		.replace(/'''?/g, "")
		.replace(/<[^>]*>/g, "")
		.replace(/&lt;/g, "<")
		.replace(/&gt;/g, ">")
		.replace(/&amp;/g, "&")
		.trim();
}

// Cuts at the last sentence that fits, so a long summary still reads whole
export function fit(text: string, room: number): string {
	const chars = [...text];
	if (chars.length <= room) return text;
	const head = chars.slice(0, room - 1).join("");
	const end = head.lastIndexOf("다. ");
	return end > 0 ? head.slice(0, end + 2) : `${head}…`;
}

export function status(text: string, url: string): string {
	return `${fit(text, LIMIT - LINK - 2)}\n\n${url}`;
}

export default async ({
	core,
	env: { LIST: list = "", SERVER, MASTODON_TOKEN },
}: {
	core: typeof Core;
	env: NodeJS.ProcessEnv;
}) => {
	const posted: Record<string, string | null> = JSON.parse(
		readFileSync(list, "utf8"),
	);
	for (const file of readdirSync("가용성")) {
		if (!file.endsWith(".wikitext")) continue;
		const title = `가용성/${file.slice(0, -".wikitext".length)}`;
		const text = summary(readFileSync(`가용성/${file}`, "utf8"));
		if (text === undefined || title in posted) continue;

		const url = `https://femiwiki.github.io/${encodeURI(title.replaceAll(" ", "_"))}`;
		const response = await fetch(`${SERVER}/api/v1/statuses`, {
			method: "POST",
			headers: {
				Authorization: `Bearer ${MASTODON_TOKEN}`,
				"Content-Type": "application/json",
				// Mastodon returns the earlier post for a repeat within an hour, so a Deploy
				// cancelled after posting but before pushing the list posts nothing twice
				"Idempotency-Key": encodeURIComponent(title),
			},
			body: JSON.stringify({
				status: status(text, url),
				visibility: "public",
				language: "ko",
			}),
		});
		if (!response.ok) {
			core.setFailed(`${title}: ${response.status} ${await response.text()}`);
			return;
		}
		const { url: post } = (await response.json()) as { url: string };
		core.info(`${title}: ${post}`);
		posted[title] = post;
		writeFileSync(list, `${JSON.stringify(posted, null, "\t")}\n`);
	}
};
