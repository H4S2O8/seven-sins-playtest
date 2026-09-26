import { Rng } from "../../rng.js";
import type { Seat } from "../../types.js";
import { runBattle } from "./engine.js";
import { Acc, camp, campaignInput, demons, pct, pp, score } from "./demons.js";

/** 探针：每关魔神降临率；每张魔神的能力实际发动多少；永眠在许愿井。 */
const n = Number(process.argv[2] ?? 6000);
const DS = demons();
const rng = new Rng(99);
console.log("== 每关：只有 1 号座带魔神时的降临率（所有魔神一样）==");
for (let st = 1; st <= 7; st++) {
  let d = 0;
  for (let i = 0; i < n; i++) if (runBattle({ ...campaignInput(rng, st), campaign: camp(DS[0], null) }).descended[0]) d++;
  console.log(`第 ${st} 关 降临 ${pct(d / n)}`);
}
console.log("\n== 能力实际发动（降临的战斗里，平均每场）==");
for (const d of DS) {
  let desc = 0; const cnt = new Map<string, number>(); let ownLife = 0, died = 0, kills = 0;
  for (let i = 0; i < n; i++) {
    const r = runBattle({ ...campaignInput(rng, 1 + rng.int(7)), campaign: camp(d, null) });
    if (!r.descended[0]) continue;
    desc++;
    for (const e of r.events) {
      if (e.type === "trigger" && e.seat === 0 && e.name === d.name) { const k = e.text.split("：")[0]; cnt.set(k, (cnt.get(k) ?? 0) + 1); }
    }
    const me = r.final[0].find((u) => u.characterId === d.id);
    if (me && !me.alive) died++;
    kills += r.events.filter((e) => e.type === "death" && e.seat === 1 && e.round >= r.descended[0]).length;
    void ownLife;
  }
  console.log(`${d.name}：${[...cnt].map(([k, v]) => `${k} ${(v / desc).toFixed(2)}`).join("，")}；魔神本场倒下 ${pct(died / desc)}；降临后敌方倒下 ${(kills / desc).toFixed(2)} 人`);
}
console.log("\n== 许愿井（第 7 关主场）有无：只有 1 号座带魔神的胜率提升 ==");
for (const d of DS) {
  const res: string[] = [];
  for (const arena of ["none", "A04"]) {
    const r2 = new Rng(5); let lift = 0;
    for (let i = 0; i < n; i++) {
      const x = campaignInput(r2, 7); x.arenaId = arena;
      lift += score(runBattle({ ...x, campaign: camp(d, null) }), 0 as Seat) - score(runBattle({ ...x, campaign: camp(null, null) }), 0 as Seat);
    }
    res.push(`${arena === "A04" ? "许愿井" : "无主场"} ${pp(lift / n)}`);
  }
  console.log(`${d.name}：${res.join("  ")}`);
}
void Acc;
