// Posts each incident report to the wiki's Mastodon status account once.
// The list of reports already posted lives on the data branch, so a report is
// posted after the Deploy that published it, whichever run that was.
import { readdirSync, readFileSync, writeFileSync } from "node:fs";
import type * as Core from "@actions/core";

// Mastodon's limit. A link counts as 23 characters whatever its length.
const LIMIT = 500;
const LINK = 23;

// The summary as the built page shows it, so templates are already expanded:
// the paragraph after the dates in the report box Template:사고 보고서 draws
export function summary(html: string): string | undefined {
	const box = html.match(
		/<div class="av-report">\s*<div class="av-when">[\s\S]*?<\/div>\s*<p>([\s\S]*?)<\/p>/,
	)?.[1];
	if (box === undefined) return undefined;
	// A missing template renders as a red link, a broken one as an error
	if (/class="(?:new|error)"/.test(box))
		throw new Error(`broken markup: ${box}`);
	const text = box
		.replace(/<[^>]*>/g, "")
		.replace(/&#(x?)([0-9a-f]+);/gi, (_, hex, code) =>
			String.fromCodePoint(Number.parseInt(code, hex ? 16 : 10)),
		)
		.replace(/&(lt|gt|quot|amp);/g, (_, name) => ENTITIES[name])
		.replace(/\s+/g, " ")
		.trim();
	if (/\{\{|\}\}|\[\[|\]\]/.test(text))
		throw new Error(`raw wikitext: ${text}`);
	return text;
}

const ENTITIES: Record<string, string> = {
	lt: "<",
	gt: ">",
	quot: '"',
	amp: "&",
};

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
	env: { LIST: list = "", SITE: site = "", SERVER, MASTODON_TOKEN },
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
		if (title in posted) continue;
		const path = title.replaceAll(" ", "_");
		let text: string | undefined;
		try {
			text = summary(readFileSync(`${site}/${path}.html`, "utf8"));
		} catch (error) {
			core.setFailed(`${title}: ${error}`);
			return;
		}
		if (text === undefined) continue;

		const url = `https://femiwiki.github.io/${encodeURI(path)}`;
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
