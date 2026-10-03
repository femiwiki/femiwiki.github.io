/* Shows the Korean times written with {{시각}} in a time zone the reader picks, the browser's by default. */
$(() => {
	const times = [...document.querySelectorAll(".fw-time")];
	if (!times.length) {
		return;
	}
	const KOREA = "Asia/Seoul";
	const STORAGE_KEY = "fw-time-zone";
	const browserZone = Intl.DateTimeFormat().resolvedOptions().timeZone;

	const loadZone = () => {
		try {
			return localStorage.getItem(STORAGE_KEY) || "";
		} catch (_error) {
			return "";
		}
	};
	const saveZone = (zone) => {
		try {
			if (zone) {
				localStorage.setItem(STORAGE_KEY, zone);
			} else {
				localStorage.removeItem(STORAGE_KEY);
			}
		} catch (_error) {
			// Without storage the choice lasts until the page is left.
		}
	};

	const instantOf = (el) => {
		const m = el.dataset.time.match(
			/^(\d{4})-(\d\d)-(\d\d) (\d\d):(\d\d)(?::(\d\d))?$/,
		);
		if (!m) {
			return null;
		}
		const [y, mo, d, h, mi, s] = m.slice(1).map((v) => Number(v || 0));
		// The written times are Korean, nine hours ahead of UTC with no daylight saving.
		return new Date(Date.UTC(y, mo - 1, d, h - 9, mi, s));
	};
	const partsIn = (zone, date) => {
		const p = Object.fromEntries(
			new Intl.DateTimeFormat("en", {
				timeZone: zone,
				year: "numeric",
				month: "2-digit",
				day: "2-digit",
				hour: "2-digit",
				minute: "2-digit",
				second: "2-digit",
				hourCycle: "h23",
				timeZoneName: "shortOffset",
			})
				.formatToParts(date)
				.map(({ type, value }) => [type, value]),
		);
		return {
			day: `${p.year}-${p.month}-${p.day}`,
			month: Number(p.month),
			date: Number(p.day),
			hour: p.hour,
			minute: p.minute,
			second: p.second,
			offset: p.timeZoneName,
		};
	};

	// The shape of the written text decides the shape of the converted one.
	const ISO = /^\d{4}-\d\d-\d\d \d\d:\d\d$/;
	const TABLE = /^(?:\d+일 )?\d\d:\d\d$/;
	const PROSE = /^(?:(\d+)월 )?(?:(\d+)일 )?\d+시(?: (\d+)분)?(?: (\d+)초)?$/;
	const proseText = (shown, previousDay, local) => {
		const m = shown.match(PROSE);
		const hasMonth = Boolean(m[1]);
		const hasDay = Boolean(m[2]);
		const withMinute = Boolean(m[3]) || local.minute !== "00";
		const withSecond = Boolean(m[4]);
		let text = `${Number(local.hour)}시`;
		if (withMinute) {
			text += ` ${Number(local.minute)}분`;
		}
		if (withSecond) {
			text += ` ${Number(local.second)}초`;
		}
		if (hasDay || local.day !== previousDay) {
			text = `${local.date}일 ${text}`;
			if (
				hasMonth ||
				local.day.slice(0, 7) !== (previousDay || "").slice(0, 7)
			) {
				text = `${local.month}월 ${text}`;
			}
		}
		return text;
	};

	const render = (zone) => {
		const korea = zone === KOREA;
		// A timeline row omits the date while it matches the row above, or the report's start for the first row.
		const start = instantOf(times[0]);
		const startDay = start ? partsIn(zone, start).day : null;
		const lastDayOf = new Map();
		// A sentence names the date only when it differs from the time read just before.
		let previousDay = startDay;
		for (const el of times) {
			if (el.dataset.shown === undefined) {
				el.dataset.shown = el.textContent;
			}
			const shown = el.dataset.shown;
			const date = instantOf(el);
			if (!date) {
				continue;
			}
			const local = partsIn(zone, date);
			const table = el.closest("table");
			let text = shown;
			if (ISO.test(shown)) {
				text = `${local.day} ${local.hour}:${local.minute}`;
			} else if (TABLE.test(shown)) {
				const previous = lastDayOf.has(table) ? lastDayOf.get(table) : startDay;
				text = `${local.hour}:${local.minute}`;
				if (local.day !== previous) {
					text = `${local.date}일 ${text}`;
				}
				lastDayOf.set(table, local.day);
			} else if (PROSE.test(shown)) {
				text = proseText(shown, previousDay, local);
			}
			previousDay = local.day;
			el.textContent = korea ? shown : text;
		}

		// Each zone label names the zone of the first time in its table or period line.
		for (const label of document.querySelectorAll(".fw-time-zone")) {
			const scope = label.closest("table, .av-when");
			const first = scope ? scope.querySelector(".fw-time") : null;
			const date = first ? instantOf(first) : null;
			if (korea || !date) {
				label.textContent = "한국 시간";
				continue;
			}
			const offset = partsIn(zone, date).offset;
			label.textContent = offset === "GMT" ? "UTC" : offset;
		}
	};

	const zones = Intl.supportedValuesOf("timeZone");
	const item = (data, label) => new OO.ui.MenuOptionWidget({ data, label });
	const items = [
		item("", `기기 시간대 (${browserZone})`),
		item(KOREA, "한국 시간"),
		item("UTC", "UTC"),
	];
	// Grouped by region like the time zone list in Special:Preferences.
	let region = null;
	for (const zone of zones) {
		const [head, ...rest] = zone.split("/");
		if (!rest.length) {
			continue;
		}
		if (head !== region) {
			region = head;
			items.push(new OO.ui.MenuSectionOptionWidget({ label: region }));
		}
		items.push(item(zone, rest.join("/").replaceAll("_", " ")));
	}
	const dropdown = new OO.ui.DropdownWidget({ menu: { items } });
	const menu = dropdown.getMenu();
	const saved = loadZone();
	menu.selectItemByData([KOREA, "UTC", ...zones].includes(saved) ? saved : "");
	const selectedZone = () => menu.findSelectedItem().getData() || browserZone;
	menu.on("select", () => {
		saveZone(menu.findSelectedItem().getData());
		render(selectedZone());
	});
	const label = new OO.ui.LabelWidget({ label: "시간대" });
	dropdown.$element.css({ width: "18em", maxWidth: "100%", margin: 0 });
	const picker = document.createElement("div");
	picker.className = "fw-time-picker";
	picker.style.cssText =
		"display:flex;justify-content:flex-end;align-items:center;gap:0.5em;margin-bottom:0.5em;";
	picker.append(label.$element[0], dropdown.$element[0]);
	document.querySelector(".mw-parser-output").prepend(picker);

	render(selectedZone());
});
