import { INTENT_RULESET } from "../src/intent/content.js";
if (String(INTENT_RULESET) !== "intent-v2")
  throw Error(
    "This audit belongs to v2; do not reinterpret historical results with the v3 engine.",
  );
import { readFileSync, writeFileSync } from "node:fs";
import { battle } from "../src/intent/battle.js";
import type { Seat, Unit } from "../src/intent/types.js";
const hands = readFileSync("reports/intent-v2-200-hands.jsonl", "utf8")
  .trim()
  .split("\n")
  .map((s) => JSON.parse(s));
let active = 0,
  changed = 0,
  decisive = 0,
  lanes = 0;
const fieldUse: Record<string, number> = {},
  examples: any[] = [];
for (const h of hands) {
  if (h.fold) continue;
  const fields = h.fields.filter((e: any) => e.active).map((e: any) => e.id);
  if (!fields.length) continue;
  active++;
  fields.forEach((f: string) => (fieldUse[f] = (fieldUse[f] || 0) + 1));
  const no = battle(h.units, [], { trace: false, initiative: h.initiative });
  const yes = battle(h.units, fields, {
    trace: false,
    initiative: h.initiative,
  });
  if (JSON.stringify(no.powers) !== JSON.stringify(yes.powers)) changed++;
  if (JSON.stringify(no.lanes) !== JSON.stringify(yes.lanes)) lanes++;
  if (no.winner !== yes.winner) {
    decisive++;
    if (examples.length < 8)
      examples.push({
        hand: h.hand,
        fields,
        before: no.powers,
        after: yes.powers,
        winnerBefore: no.winner,
        winnerAfter: yes.winner,
      });
  }
}
const model = JSON.parse(
  readFileSync("reports/intent-v2-model-5.json", "utf8"),
);
const five = model.map((g: any) => ({
  id: g.id,
  fold: g.result.fold,
  modelWon: g.result.winner === g.modelSeat,
  tie: g.result.winner === null,
  net: g.stacks[g.modelSeat] - 100,
  decisions: g.modelDecisions,
  powers: g.result.battle?.powers,
}));
const g = model[4],
  actual = g.revealed as [Unit[], Unit[]];
const old = structuredClone(actual),
  s = g.modelSeat as Seat;
old[s][0].plan = { on: true, targets: [{ side: "ally", pos: 1 }], mode: 0 };
old[s][1].plan = {
  on: true,
  targets: [
    { side: "ally", pos: 0 },
    { side: "ally", pos: 2 },
  ],
  mode: 0,
};
old[s][2].plan = { on: false, targets: [], mode: 0 };
const previousPlan = battle(old, [], { trace: false, initiative: s });
const report = {
  method:
    "Fixed final plans: removing terrain is a mechanical attribution, not evidence that players would make the same decisions without terrain. Model hand-five old-route comparison uses revealed opponent only after play; it is a hindsight diagnostic, not an available winning strategy.",
  showdowns: hands.filter((h) => !h.fold).length,
  active,
  changed,
  lanes,
  decisive,
  fieldUse,
  examples,
  five,
  model5PreviousPlan: {
    powers: previousPlan.powers,
    winner: previousPlan.winner,
  },
};
writeFileSync(
  "reports/intent-v2-result-audit.json",
  JSON.stringify(report, null, 2),
);
console.log(JSON.stringify(report));
