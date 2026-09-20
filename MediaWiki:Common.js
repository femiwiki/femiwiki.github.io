/* "모두 펼치기 / 모두 접기" for the details trees on the cost pages. */
$(() => {
	for (const tree of document.querySelectorAll(".cost-tree")) {
		const bar = document.createElement("div");
		bar.className = "cost-tree-all";
		[
			["모두 펼치기", true],
			["모두 접기", false],
		].forEach(([text, open], i) => {
			if (i) {
				bar.append(" · ");
			}
			const a = document.createElement("a");
			a.href = "#";
			a.textContent = text;
			a.addEventListener("click", (e) => {
				e.preventDefault();
				for (const d of tree.querySelectorAll("details")) {
					d.open = open;
				}
			});
			bar.append(a);
		});
		tree.prepend(bar);
	}
});
