import { INTENT_RULESET } from "../src/intent/content.js";
if (String(INTENT_RULESET) !== "intent-v3")
  throw Error("Historical v3 audit: cannot replay with a different ruleset.");
import { readFileSync, writeFileSync } from "node:fs";
import { battle } from "../src/intent/battle.js";
const hands = readFileSync("reports/intent-v3-200-hands.jsonl", "utf8")
  .trim()
  .split("\n")
  .map((x) => JSON.parse(x));
const groups: Record<string, any> = {},
  fields: Record<string, any> = {};
let decisive = 0,
  changedLanes = 0;
for (const h of hands) {
  const active = h.fields.filter((f: any) => f.active).map((f: any) => f.id);
  const full = battle(h.units, active, {
    trace: false,
    initiative: h.initiative,
  });
  const none = battle(h.units, [], { trace: false, initiative: h.initiative });
  if (!h.fold) {
    decisive += full.winner !== none.winner ? 1 : 0;
    changedLanes +=
      JSON.stringify(full.lanes) !== JSON.stringify(none.lanes) ? 1 : 0;
  }
  for (let s = 0; s < 2; s++) {
    const raw = h.units[s].map((u: any) => u.raw),
      key = raw.every((n: number) => n >= 8)
        ? "threeHigh"
        : raw.every((n: number) => n <= 5)
          ? "threeLow"
          : "other";
    const g = (groups[key] ??= {
      n: 0,
      wins: 0,
      ties: 0,
      net: 0,
      showdowns: 0,
      showdownWins: 0,
      gear: 0,
      fieldChangedOutcome: 0,
    });
    g.n++;
    g.wins += h.winner === s ? 1 : 0;
    g.ties += h.winner === null ? 1 : 0;
    g.net += h.stacks[s] - 100;
    g.gear += h.units[s].filter((u: any) => u.gear).length;
    if (!h.fold) {
      g.showdowns++;
      g.showdownWins += h.winner === s ? 1 : 0;
      g.fieldChangedOutcome += full.winner !== none.winner ? 1 : 0;
    }
  }
  const key = h.fields[0].id,
    f = (fields[key] ??= { n: 0, folds: 0, showdowns: 0, decisive: 0 });
  f.n++;
  f.folds += h.fold ? 1 : 0;
  if (!h.fold) {
    f.showdowns++;
    f.decisive += full.winner !== none.winner ? 1 : 0;
  }
}
const model = JSON.parse(
  readFileSync("reports/intent-v3-model-5.json", "utf8"),
);
const modelFields = [
  ["F3", "F6", "F4", "F2"],
  ["F2", "F1"],
  ["F7", "F4"],
  ["F7", "F5", "F3"],
  ["F5", "F4", "F1"],
];
const five = model.map((g: any, i: number) => {
  const resolved = battle(g.revealed, modelFields[i], {
    trace: false,
    initiative: i % 2 === 0 ? g.modelSeat : 1 - g.modelSeat,
  });
  return {
    id: g.id,
    fold: g.result.fold,
    winner: g.result.winner,
    seat: g.modelSeat,
    net: g.stacks[g.modelSeat] - 100,
    decisions: g.modelDecisions,
    powers: resolved.powers,
    frozenShowdownWinner: resolved.winner,
    incorrectFoldAgainstFrozenPlan:
      g.result.fold &&
      g.result.winner !== g.modelSeat &&
      resolved.winner === g.modelSeat,
  };
});
const g = model[0],
  withoutSleep = structuredClone(g.revealed);
withoutSleep[g.modelSeat][2].plan = { on: false, targets: [], mode: 0 };
const sleepOff = battle(withoutSleep, modelFields[0], {
  trace: false,
  initiative: 0,
});
const report = {
  protocol: "intent-v3",
  method:
    "All 200 independent hands; high=8..10, low=3..5. Groups reflect naturally dealt samples and all final outcomes, not controlled balance trials. Terrain removal holds final choices fixed. Model fold diagnostics use revealed truth only after completion and cannot establish the ex-ante correct decision.",
  groups,
  openingFields: fields,
  showdowns: hands.filter((h) => !h.fold).length,
  fieldDecisive: decisive,
  fieldChangedLanes: changedLanes,
  five,
  model1WithoutSleep: { powers: sleepOff.powers, winner: sleepOff.winner },
};
writeFileSync(
  "reports/intent-v3-result-audit.json",
  JSON.stringify(report, null, 2),
);
console.log(JSON.stringify(report));
