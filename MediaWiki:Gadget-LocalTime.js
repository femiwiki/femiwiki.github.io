/* Shows the Korean times written with {{시각}} in the reader's time zone. */
$(() => {
	const KST_OFFSET_HOURS = 9;
	const format = new Intl.DateTimeFormat("en", {
		year: "numeric",
		month: "2-digit",
		day: "2-digit",
		hour: "2-digit",
		minute: "2-digit",
		hourCycle: "h23",
		timeZoneName: "shortOffset",
	});
	const toLocal = (el) => {
		const m = el.dataset.time.match(/^(\d{4})-(\d\d)-(\d\d) (\d\d):(\d\d)$/);
		if (!m) {
			return null;
		}
		const [y, mo, d, h, mi] = m.slice(1).map(Number);
		const date = new Date(Date.UTC(y, mo - 1, d, h - KST_OFFSET_HOURS, mi));
		const p = Object.fromEntries(
			format.formatToParts(date).map(({ type, value }) => [type, value]),
		);
		return {
			day: `${p.year}-${p.month}-${p.day}`,
			time: `${p.hour}:${p.minute}`,
			dayOfMonth: Number(p.day),
			zone: p.timeZoneName,
		};
	};

	const times = [...document.querySelectorAll(".fw-time")];
	// A timeline row omits the date while it matches the row above, or the report's start for the first row.
	const start = times.length ? toLocal(times[0]) : null;
	const startDay = start ? start.day : null;
	const lastDayOf = new Map();
	for (const el of times) {
		const local = toLocal(el);
		if (!local) {
			continue;
		}
		const table = el.closest("table");
		const sameDay =
			local.day === (lastDayOf.has(table) ? lastDayOf.get(table) : startDay);
		lastDayOf.set(table, local.day);
		if (`${local.day} ${local.time}` === el.dataset.time) {
			continue;
		}
		el.title = `한국 시간 ${el.dataset.time}`;
		if (!el.classList.contains("fw-time-short")) {
			el.textContent = `${local.day} ${local.time} (${local.zone})`;
		} else if (sameDay) {
			el.textContent = local.time;
		} else {
			el.textContent = `${local.dayOfMonth}일 ${local.time}`;
		}
	}
});
