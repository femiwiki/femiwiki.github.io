/* The switch that shows what was used for free on the details trees on the cost pages. */
$(() => {
	for (const tree of document.querySelectorAll(".cost-tree")) {
		if (!tree.querySelector(".cost-free")) {
			continue;
		}
		let bar = tree.querySelector(":scope > .cost-tree-all");
		if (!bar) {
			bar = document.createElement("div");
			bar.className = "cost-tree-all";
			tree.prepend(bar);
		}
		const label = document.createElement("label");
		const box = document.createElement("input");
		box.type = "checkbox";
		box.addEventListener("change", () => {
			tree.classList.toggle("cost-show-free", box.checked);
		});
		label.append(box, " 0원인 사용도 보이기");
		bar.append(bar.childNodes.length ? " · " : "", label);
	}
});
