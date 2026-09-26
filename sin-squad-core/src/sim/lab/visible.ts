import { Rng } from "../../rng.js";
import { runBattle } from "./engine.js";
import { camp, campaignInput, demons, pct } from "./demons.js";

/** 降临的战斗里，魔神的能力“看得见地发生了”的比例，以及魔神本人出手 / 反击的次数。 */
const n = Number(process.argv[2] ?? 8000);
const over = process.argv[3] ? JSON.parse(process.argv[3]) : {};
const both = process.argv[4] === "both";
const DS = demons(over);
for (const d of DS) {
  const rng = new Rng(11);
  let desc = 0, visible = 0, acts = 0, recoils = 0, after = 0;
  for (let i = 0; i < n; i++) {
    const foeDemon = both ? DS[rng.int(DS.length)] : null;
    const r = runBattle({ ...campaignInput(rng, 1 + rng.int(7)), campaign: camp(d, foeDemon) });
    if (!r.descended[0]) continue;
    desc++;
    const pos = r.final[0].findIndex((u) => u.characterId === d.id);
    const mine = (e: { seat: number; pos: number }) => e.seat === 0 && e.pos === pos;
    const a = r.events.filter((e) => e.type === "attack" && mine(e) && e.round >= r.descended[0]).length;
    const rc = r.events.filter((e) => e.type === "recoil" && mine(e)).length;
    acts += a; recoils += rc;
    after += r.rounds - r.descended[0] + 1;
    const trig = r.events.filter((e) => e.type === "trigger" && mine(e) && e.name === d.name && e.text !== "魔神降临");
    let vis = false;
    switch (d.name) {
      case "晨星": vis = r.events.some((e) => e.type === "attack" && mine(e)) ; break;
      case "焚怒": vis = r.events.filter((e) => e.type === "attack" && mine(e)).length >= 2 || rc > 0; break;
      case "永眠": vis = rc > 0; break;
      case "金山": vis = r.interest[0] > 0; break;
      default: vis = trig.length > (d.name === "欲之王" ? 0 : 0);
    }
    if (vis) visible++;
  }
  console.log(`${d.name.padEnd(5, "　")} 降临 ${desc} 场 · 能力看得见 ${pct(visible / desc)} · 她出手 ${(acts / desc).toFixed(2)} 次、反击 ${(recoils / desc).toFixed(2)} 次 · 降临后还打 ${(after / desc).toFixed(2)} 轮`);
}
