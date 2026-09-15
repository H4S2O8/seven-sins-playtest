import * as P from "./progression.mjs";
export function showWorkshop({
  overlay,
  save,
  design,
  sins,
  persist,
  back,
  index = 0,
}) {
  const sin = sins[index],
    tree = design.trees.find((t) => t.id === P.CODES[sin.id]);
  overlay.hidden = false;
  overlay.innerHTML =
    '<div class="panel workshop"><span class="eyebrow">DESIRE ARCHITECTURE / 永久能力</span><div class="work-head"><h2>欲望构筑</h2><button id="work-back">返回基地</button></div><p id="work-summary"></p><nav id="work-tabs"></nav><div id="work-feedback" role="status"></div><h3>普攻形态 · 不占技能槽</h3><div id="basic-grid"></div><h3 id="slot-title"></h3><button id="slot-buy">扩充技能槽</button><p class="muted">主动与被动共用槽位。普攻随当前罪值切换形态，不消耗罪。技能按装备顺序绑定 Q / E / R / T / G。</p><div id="skill-grid"></div></div>';
  const q = (s) => overlay.querySelector(s),
    refresh = () =>
      showWorkshop({ overlay, save, design, sins, persist, back, index });
  q("#work-back").onclick = back;
  q("#work-summary").textContent =
    `可用痛苦材料 ${Math.floor(save.currency)} · ${tree.name} · ${tree.base}`;
  sins.forEach((s, i) => {
    const b = document.createElement("button");
    b.textContent = s.name;
    b.disabled = i >= save.unlocked;
    b.className = i === index ? "chosen" : "";
    b.onclick = () =>
      showWorkshop({ overlay, save, design, sins, persist, back, index: i });
    q("#work-tabs").append(b);
  });
  const action = (result) => {
    if (result) {
      q("#work-feedback").textContent = result;
      return;
    }
    persist();
    refresh();
  };
  const forms = design.basics[tree.id];
  for (let i = 0; i < 6; i++) {
    const card = document.createElement("article");
    card.className = "basic-card";
    const title = document.createElement("strong");
    title.textContent = `${design.bands[i]}罪 · 等级${save.basicRanks[tree.id][i] + 1}`;
    const desc = document.createElement("p");
    desc.textContent = forms?.shapes?.[i] || `第${i + 1}形态`;
    const b = document.createElement("button"),
      rank = save.basicRanks[tree.id][i],
      stats = document.createElement("p");
    stats.className = "numbers";
    stats.textContent = `伤害 ${(forms.damage[i] * (1 + 0.1 * rank)).toFixed(1)} · 范围 ${(forms.range[i] * (1 + 0.025 * rank)).toFixed(2)}米 · 间隔 ${Math.max(0.15, forms.interval[i] - (sin.id === "gluttony" ? 0.1 : 0.02) * rank).toFixed(2)}秒`;
    b.textContent =
      rank === 2
        ? "已满级"
        : `强化 · ${[30, 50, 80, 120, 180, 260][i] * (rank + 1)}材料`;
    b.disabled = rank === 2;
    b.onclick = () => action(P.buyBasic(save, tree.id, i));
    card.append(title, desc, stats, b);
    q("#basic-grid").append(card);
  }
  q("#slot-title").textContent =
    `${tree.name}技能 · 已装备 ${save.equipped[tree.id].length}/${save.slots[tree.id]}`;
  const slots = save.slots[tree.id];
  q("#slot-buy").textContent =
    slots >= 5
      ? "技能槽已满"
      : `扩充至${slots + 1}槽 · ${[300, 800, 1800][slots - 2]}材料`;
  q("#slot-buy").disabled = slots >= 5;
  q("#slot-buy").onclick = () => action(P.buySlot(save, tree.id));
  tree.nodes.forEach((n) => {
    const card = document.createElement("article");
    card.className = "skill-card";
    const rank = save.learned[n.code] || 0,
      on = save.equipped[tree.id].includes(n.code);
    card.classList.toggle("equipped", on);
    const h = document.createElement("h4");
    h.textContent = `${n.code} ${n.name} · ${n.type} · ${rank}/3`;
    const d = document.createElement("p");
    d.textContent = n.desc;
    const numbers = document.createElement("p");
    numbers.className = "numbers";
    numbers.textContent = n.ranks[Math.max(0, rank - 1)];
    const meta = document.createElement("small");
    meta.textContent = `${n.cast || "被动"}${n.cd ? " · 冷却 " + n.cd : ""} · 前置：${n.parents.map(([i, r]) => `${tree.id}${String(i).padStart(2, "0")} ≥${r}级`).join("、") || "无"}`;
    const note = document.createElement("p");
    note.className = "muted";
    note.textContent = n.note;
    const learn = document.createElement("button");
    learn.textContent =
      rank === 3
        ? "已满级"
        : `${rank ? "升级" : "学习"} · ${P.skillPrice(n, rank)}材料`;
    learn.disabled = rank === 3;
    learn.onclick = () => action(P.learn(save, tree, n));
    const eq = document.createElement("button");
    eq.textContent = on ? "卸下" : "装备";
    eq.disabled = !rank;
    eq.onclick = () => action(P.equip(save, tree.id, n.code));
    card.append(h, d, numbers, meta, note, learn, eq);
    q("#skill-grid").append(card);
  });
}
