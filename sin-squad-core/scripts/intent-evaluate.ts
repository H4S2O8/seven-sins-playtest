import { mkdirSync, writeFileSync } from "node:fs";
import { performance } from "node:perf_hooks";
import { battle } from "../src/intent/battle.js";
import {
  Bot,
  forecast,
  hypotheses,
  optimise,
  PERMS,
  type Forecast,
} from "../src/intent/agent.js";
import { CARDS } from "../src/intent/content.js";
import { IntentTable, tier } from "../src/intent/table.js";
import {
  OFF,
  type Observation,
  type Seat,
  type Unit,
} from "../src/intent/types.js";

const count = Number(process.argv[2] || 1000),
  start = Number(process.argv[3] || 730001);
if (!Number.isInteger(count) || count < 1) throw Error("Invalid hand count");
const started = performance.now();
const rows: any[] = [],
  layoutRows: any[] = [],
  decisionRows: any[] = [],
  styles = ["balanced", "cautious", "pressure"] as const;
const stats: any = {
  hands: count,
  seedStart: start,
  protocol: "intent-v4",
  folds: 0,
  earlyFolds: 0,
  midFolds: 0,
  showdowns: 0,
  ties: 0,
  actions: 0,
  paidOffers: 0,
  awkwardOffers: 0,
  gear: 0,
  duplicates: 0,
  rawSumLargerWins: 0,
  rawSumComparable: 0,
  normalCandidates: 0,
  upsets: 0,
  comboUpsets: 0,
  regretCandidates: 0,
  regretAudited: 0,
  seatWins: [0, 0],
  style: {},
  cards: Object.fromEntries(
    CARDS.map((c) => [c.id, { selected: 0, on: 0, wins: 0 }]),
  ),
  brier: 0,
  forecastCount: 0,
  calibration: Array.from({ length: 5 }, (_, i) => ({
    from: i / 5,
    to: (i + 1) / 5,
    n: 0,
    predicted: 0,
    actual: 0,
  })),
  signals: {
    before: { char: 0, tier: 0, n: 0 },
    gear: { char: 0, tier: 0, n: 0 },
    after: { char: 0, tier: 0, n: 0 },
  },
  seatSwapFailures: 0,
};
const indexMax = (xs: number[]) => xs.indexOf(Math.max(...xs));
const outcome = (winner: Seat | null, s: Seat) =>
  winner === null ? 0.5 : winner === s ? 1 : 0;
function auditPrediction(
  o: Observation,
  actual: Unit[],
  key: "before" | "gear" | "after",
) {
  const samples = hypotheses(o, 48, key === "after", key !== "before", 991),
    bucket = stats.signals[key];
  for (let p = 0; p < 3; p++) {
    const ids = CARDS.map(
        (c) => samples.filter((w) => w[p].id === c.id).length,
      ),
      tiers = [0, 1, 2].map(
        (t) => samples.filter((w) => tier(w[p].raw) === t).length,
      );
    bucket.char += CARDS[indexMax(ids)].id === actual[p].id ? 1 : 0;
    bucket.tier += indexMax(tiers) === tier(actual[p].raw) ? 1 : 0;
    bucket.n++;
  }
}
function layoutAudit(o: Observation) {
  const training = hypotheses(o, 4, true, true, 313),
    validation = hypotheses(o, 32, true, true, 617);
  const without = {
    ...o,
    effects: o.effects.map((e) => ({ ...e, active: false })),
  };
  const candidates: {
    own: Unit[];
    plain: Unit[];
    score: number;
    plainScore: number;
  }[] = [];
  for (const units of PERMS)
    for (const numbers of PERMS) {
      const initial = units.map((i, p) => ({
        id: o.me.kept[i],
        raw: o.me.numbers[numbers[p]],
        gear: null,
        plan: OFF(),
      }));
      const own = optimise(o, initial, training, 2),
        plain = optimise(without, initial, training, 2);
      candidates.push({
        own,
        plain,
        score: forecast(o, own, training).score,
        plainScore: forecast(without, plain, training).score,
      });
    }
  const chosen = candidates.slice().sort((a, b) => b.score - a.score)[0].own;
  const plain = candidates
    .slice()
    .sort((a, b) => b.plainScore - a.plainScore)[0].plain;
  const layoutChanged =
    JSON.stringify(chosen.map((u) => [u.id, u.raw])) !==
    JSON.stringify(plain.map((u) => [u.id, u.raw]));
  const gain =
    forecast(o, chosen, validation).score -
    forecast(o, plain, validation).score;
  const gainWithout =
    forecast(without, chosen, validation).score -
    forecast(without, plain, validation).score;
  return {
    opening: o.effects[0].id,
    layoutChanged,
    positive: layoutChanged && gain > 0.2,
    validationGap: gain,
    fieldContribution: gain - gainWithout,
    chosen,
    plain,
    tiers: o.foe.tiers,
  };
}

for (let i = 0; i < count; i++) {
  const t = new IntentTable(start + i, (i % 2) as Seat),
    profile = [styles[i % 3], styles[Math.floor(i / 3) % 3]],
    bots = [
      new Bot(100000 + i * 2, profile[0]),
      new Bot(100001 + i * 2, profile[1]),
    ];
  const last: (Forecast | null)[] = [null, null],
    lastObs: (Observation | null)[] = [null, null],
    regret: (Unit[] | null)[] = [null, null];
  const decisions: any[] = [];
  let actions = 0,
    foldRound = 0;
  while (!t.result) {
    const s = t.actors()[0],
      o = t.observe(s),
      d = bots[s].decide(o);
    if (i < 100 && s === 0 && o.phase === "place")
      layoutRows.push({ hand: i, ...layoutAudit(o) });
    if (d.forecast && o.phase === "bet") {
      last[s] = d.forecast;
      lastObs[s] = o;
    }
    if (d.action.type === "fold") foldRound = t.round;
    if (d.action.type === "equip") {
      stats.paidOffers++;
      const worlds = hypotheses(o, 8),
        base = forecast(o, o.me.units!, worlds).score;
      let best = -Infinity;
      for (const g of o.me.gearOffers)
        for (let p = 0; p < 3; p++)
          if (!o.me.units![p].gear) {
            const units = structuredClone(o.me.units!);
            units[p].gear = g;
            best = Math.max(best, forecast(o, units, worlds).score);
          }
      if (best <= base + 1e-7) stats.awkwardOffers++;
    }
    // Extra search is committed now, before the other player's new secret plan is visible.
    if (
      i < 100 &&
      o.phase === "plan" &&
      o.round === 3 &&
      d.action.type === "plan"
    ) {
      stats.regretAudited++;
      const own = structuredClone(o.me.units!);
      own.forEach(
        (u, p) =>
          (u.plan = d.action.type === "plan" ? d.action.plans[p] : OFF()),
      );
      const worlds = hypotheses(o, 16, true, true, 191),
        alternative = optimise(o, own, worlds, 2);
      if (
        forecast(o, alternative, worlds).score >
        forecast(o, own, worlds).score + 0.25
      )
        regret[s] = alternative;
    }
    decisions.push({
      seat: s,
      round: o.round,
      phase: o.phase,
      action: d.action,
      forecast: d.forecast,
      reason: d.reason,
    });
    t.act(s, d.action);
    if (++actions > 300) throw Error(`Nonterminating hand ${i}`);
  }
  stats.actions += actions;
  const actual = battle(
    t.units as [Unit[], Unit[]],
    t.effects.filter((e) => e.active).map((e) => e.id),
    { trace: false, initiative: t.initiative },
  );
  const swap = battle(
    [t.units[1]!, t.units[0]!],
    t.effects.filter((e) => e.active).map((e) => e.id),
    { trace: false, initiative: (1 - t.initiative) as Seat },
  );
  if (
    JSON.stringify(actual.powers) !==
    JSON.stringify([swap.powers[1], swap.powers[0]])
  )
    stats.seatSwapFailures++;
  if (t.result.fold) {
    stats.folds++;
    if (foldRound <= 1) stats.earlyFolds++;
    else stats.midFolds++;
  } else {
    stats.showdowns++;
    if (t.result.winner === null) stats.ties++;
  }
  if (t.result.winner !== null) stats.seatWins[t.result.winner]++;
  let normal = false,
    upset = false;
  for (const s of [0, 1] as Seat[]) {
    const units = t.units[s]!,
      pred = last[s],
      style = profile[s];
    const group = (stats.style[style] ??= { hands: 0, net: 0, folded: 0 });
    group.hands++;
    group.net += t.stacks[s] - 100;
    if (t.result.fold && t.result.winner !== s) group.folded++;
    stats.duplicates += new Set(units.map((u) => u.id)).size < 3 ? 1 : 0;
    for (const u of units) {
      stats.gear += u.gear ? 1 : 0;
      const c = stats.cards[u.id];
      c.selected++;
      c.on += u.plan.on ? 1 : 0;
      c.wins += outcome(t.result.winner, s);
    }
    if (pred && !t.result.fold) {
      const p = pred.win + pred.tie / 2,
        y = outcome(actual.winner, s),
        bin = stats.calibration[Math.min(4, Math.floor(p * 5))];
      stats.brier += (p - y) ** 2;
      stats.forecastCount++;
      bin.n++;
      bin.predicted += p;
      bin.actual += y;
      normal ||= (p >= 0.65 && y === 1) || (p <= 0.35 && y === 0);
      upset ||= (p <= 0.3 && y === 1) || (p >= 0.7 && y === 0);
    }
    if (lastObs[s])
      for (const key of ["before", "gear", "after"] as const)
        auditPrediction(lastObs[s]!, t.units[(1 - s) as Seat]!, key);
    if (regret[s] && !t.result.fold) {
      const sides = structuredClone(t.units) as [Unit[], Unit[]];
      sides[s] = regret[s]!;
      const better = battle(
        sides,
        t.effects.filter((e) => e.active).map((e) => e.id),
        { trace: false, initiative: t.initiative },
      );
      if (outcome(better.winner, s) > outcome(actual.winner, s))
        stats.regretCandidates++;
    }
  }
  stats.normalCandidates += normal ? 1 : 0;
  stats.upsets += upset ? 1 : 0;
  const noGear = battle(
    t.units as [Unit[], Unit[]],
    t.effects.filter((e) => e.active).map((e) => e.id),
    { gearEffects: false, trace: false, initiative: t.initiative },
  );
  const noSkill = battle(
    t.units as [Unit[], Unit[]],
    t.effects.filter((e) => e.active).map((e) => e.id),
    { skills: false, trace: false, initiative: t.initiative },
  );
  const comboChange =
    noGear.winner !== actual.winner || noSkill.winner !== actual.winner;
  if (upset && comboChange) stats.comboUpsets++;
  const sums = t.units.map((team) => team!.reduce((n, u) => n + u.raw, 0));
  if (!t.result.fold && actual.winner !== null && sums[0] !== sums[1]) {
    stats.rawSumComparable++;
    if (actual.winner === (sums[0] > sums[1] ? 0 : 1)) stats.rawSumLargerWins++;
  }
  rows.push({
    hand: i,
    seed: start + i,
    initiative: t.initiative,
    fields: t.effects,
    profiles: profile,
    fold: t.result.fold,
    foldRound,
    winner: t.result.winner,
    counterfactualWinner: actual.winner,
    powers: actual.powers,
    stacks: t.stacks,
    fees: t.spent,
    units: t.units,
    normal,
    upset,
    comboChange,
    forecasts: last,
  });
  decisionRows.push({ hand: i, decisions });
  if ((i + 1) % 50 === 0)
    console.log(
      JSON.stringify({
        done: i + 1,
        total: count,
        seconds: Math.round((performance.now() - started) / 1000),
        folds: stats.folds,
      }),
    );
}
stats.seconds = (performance.now() - started) / 1000;
stats.layout = {
  sample: layoutRows.length,
  positive: null,
  skillSupported: null,
  method:
    "Unavailable in v3: base-arena conventional order removed. Old metric is intentionally not reused.",
};
stats.processLayout = {
  sample: layoutRows.length,
  changed: layoutRows.filter((r) => r.layoutChanged).length,
  positive: layoutRows.filter((r) => r.positive).length,
  fieldSupported: layoutRows.filter(
    (r) => r.positive && r.fieldContribution > 0.2,
  ).length,
  method:
    "First 100 dealt seat-zero situations. Joint arrangement/skill optimization with and without the revealed opening field, same search budget and same opponent samples. Independent validation salt. Measures value of adapting to the opening process field, NOT unconventional layouts versus the old arena baseline or human genius.",
};
stats.metrics = {
  foldRate: stats.folds / count,
  meanGear: stats.gear / (count * 2),
  meanBrier: stats.brier / Math.max(1, stats.forecastCount),
  awkwardRate: stats.awkwardOffers / Math.max(1, stats.paidOffers),
  largerRawSumWinRate:
    stats.rawSumLargerWins / Math.max(1, stats.rawSumComparable),
};
mkdirSync("reports", { recursive: true });
const prefix = `reports/intent-v4-${count}`;
writeFileSync(prefix + ".json", JSON.stringify(stats, null, 2));
writeFileSync(
  prefix + "-hands.jsonl",
  rows.map((r) => JSON.stringify(r)).join("\n"),
);
writeFileSync(
  prefix + "-decisions.jsonl",
  decisionRows.map((r) => JSON.stringify(r)).join("\n"),
);
writeFileSync(prefix + "-layouts.json", JSON.stringify(layoutRows, null, 2));
console.log(JSON.stringify(stats, null, 2));
