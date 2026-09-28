import { INTENT_RULESET } from "../src/intent/content.js";
if (String(INTENT_RULESET) !== "intent-v3")
  throw Error("Historical v3 audit: cannot replay with a different ruleset.");
import { readFileSync, writeFileSync } from "node:fs";
import { IntentTable } from "../src/intent/table.js";
import { forecast, hypotheses, optimise } from "../src/intent/agent.js";
import { battle } from "../src/intent/battle.js";
import { publicReads } from "../src/intent/information.js";
import type { Seat, Unit } from "../src/intent/types.js";

// Audit existing dealt hands, never add new games or expose truth to the selector.
const prefix = "reports/intent-v3-200";
const hands = readFileSync(prefix + "-hands.jsonl", "utf8")
  .trim()
  .split("\n")
  .map((x) => JSON.parse(x));
const logs = readFileSync(prefix + "-decisions.jsonl", "utf8")
  .trim()
  .split("\n")
  .map((x) => JSON.parse(x));
const rows: any[] = [];
for (let i = 0; i < hands.length && rows.length < 40; i++) {
  const h = hands[i],
    t = new IntentTable(h.seed, h.initiative);
  for (const d of logs[i].decisions) {
    if (d.phase === "plan" && d.round === 3 && rows.length < 40) {
      const s = d.seat as Seat,
        o = t.observe(s),
        start = structuredClone(o.me.units!);
      const blind = optimise(
        o,
        start,
        hypotheses(o, 12, false, false, 1901),
        2,
      );
      const informed = optimise(
        o,
        start,
        hypotheses(o, 12, true, true, 1901),
        2,
      );
      // Truth enters ONLY after both decisions have been committed above.
      const result = (own: Unit[]) => {
        const b = battle(
          [own, h.units[1 - s]],
          o.effects.filter((e) => e.active).map((e) => e.id!),
          { trace: false, initiative: o.initiative === s ? 0 : 1 },
        );
        return {
          equity: b.winner === 0 ? 1 : b.winner === null ? 0.5 : 0,
          powers: b.powers,
        };
      };
      const before = result(blind),
        after = result(informed);
      rows.push({
        hand: i,
        seat: s,
        changed:
          JSON.stringify(blind.map((u) => u.plan)) !==
          JSON.stringify(informed.map((u) => u.plan)),
        before,
        after,
        delta: after.equity - before.equity,
        reads: publicReads(o),
        blind,
        informed,
      });
    }
    t.act(d.seat, d.action);
  }
}
const report = {
  protocol: "intent-v3",
  method:
    "First 40 round-three plan opportunities in the already completed 200 hands. Same own cards, search budget and public process fields. Remove opponent equipment and intent evidence only from the blind belief model. Select before accessing final hidden truth. Opponent final plans are held fixed; this is a paired counterfactual showdown audit, not a new match win rate or proof of human enjoyment.",
  n: rows.length,
  changed: rows.filter((r) => r.changed).length,
  better: rows.filter((r) => r.delta > 0).length,
  worse: rows.filter((r) => r.delta < 0).length,
  equal: rows.filter((r) => r.delta === 0).length,
  equityDelta: rows.reduce((n, r) => n + r.delta, 0) / Math.max(1, rows.length),
  rows,
};
writeFileSync(
  "reports/intent-v3-information-audit.json",
  JSON.stringify(report, null, 2),
);
console.log(JSON.stringify({ ...report, rows: undefined }));
