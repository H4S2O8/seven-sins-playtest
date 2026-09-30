import { readFileSync, writeFileSync, mkdirSync, existsSync } from "node:fs";
import { randomBytes } from "node:crypto";
import { Rng } from "../src/rng.js";
import { Bot } from "../src/intent/agent.js";
import { IntentTable } from "../src/intent/table.js";
import type { Action, Observation, Seat } from "../src/intent/types.js";

const file = "reports/intent-v4-model-session.private.json";
type Game = {
  id: number;
  seed: number;
  seat: Seat;
  botState: number;
  actions: { seat: Seat; action: Action }[];
  model: {
    observation: Observation;
    action: Action;
    probability: number | null;
    reason: string;
  }[];
};
const command = process.argv[2] || "show";
let games: Game[];
if (command === "init") {
  if (existsSync(file))
    throw Error("Session already exists; do not overwrite real model evidence");
  games = Array.from({ length: 5 }, (_, id) => ({
    id: id + 1,
    seed: randomBytes(4).readUInt32LE(),
    seat: (id % 2) as Seat,
    botState: randomBytes(4).readUInt32LE(),
    actions: [],
    model: [],
  }));
} else games = JSON.parse(readFileSync(file, "utf8"));
// Seats are relabelled between hands; actual model/opponent initiative alternates 1,0,1,0.
const replay = (g: Game) => {
  const t = new IntentTable(
    g.seed,
    g.id % 2 === 1 ? g.seat : ((1 - g.seat) as Seat),
  );
  for (const a of g.actions) t.act(a.seat, a.action);
  return t;
};
const input: {
  id: number;
  action: Action;
  probability?: number;
  reason: string;
}[] =
  command === "act" ? JSON.parse(readFileSync(process.argv[3], "utf8")) : [];
// Validate every requested model move before writing anything, including failed batches.
for (const move of input) {
  const g = games.find((g) => g.id === move.id);
  if (!g) throw Error("Unknown hand");
  if (
    !move.reason ||
    (move.probability !== undefined &&
      (!Number.isFinite(move.probability) ||
        move.probability < 0 ||
        move.probability > 1))
  )
    throw Error("Invalid model rationale/probability");
  const t = replay(g);
  const observation = t.observe(g.seat);
  t.act(g.seat, move.action);
  g.model.push({
    observation,
    action: move.action,
    probability: move.probability ?? null,
    reason: move.reason,
  });
  g.actions.push({ seat: g.seat, action: move.action });
}
const visible = [];
let complete = 0;
for (const g of games) {
  const t = replay(g),
    bot = new Bot(
      1,
      ["balanced", "cautious", "pressure"][g.id % 3] as "balanced",
    );
  bot.rng = Rng.restore(g.botState);
  while (!t.result && !t.actors().includes(g.seat)) {
    const s = t.actors()[0],
      d = bot.decide(t.observe(s));
    t.act(s, d.action);
    g.actions.push({ seat: s, action: d.action });
    if (g.actions.length > 300) throw Error("Nontermination");
  }
  g.botState = bot.rng.snapshot();
  if (t.result) {
    complete++;
    continue;
  }
  const o = t.observe(g.seat);
  visible.push({
    id: g.id,
    phase: o.phase,
    r: o.round,
    first: o.initiative === g.seat,
    fields: o.effects.map((e) => [e.id, e.active]),
    ...(["draft", "place"].includes(o.phase) ? { nums: o.me.numbers } : {}),
    ...(o.phase === "draft" ? { draft: o.me.offer } : {}),
    ...(o.phase === "place" ? { kept: o.me.kept } : {}),
    own: o.me.units?.map((u) => [
      u.id,
      u.raw,
      u.gear,
      u.plan.on
        ? `${u.plan.mode}:${u.plan.targets.map((t) => t.side[0] + t.pos).join(",")}`
        : "off",
    ]),
    enemy: {
      tiers: o.foe.tiers,
      equipment: o.foe.equipment,
      signals: o.foe.signals.map((s) =>
        s.on
          ? `${s.kind}:${s.targets.map((t) => t.side[0] + t.pos).join(",")}`
          : "off",
      ),
    },
    stack: [o.stacks[g.seat], o.stacks[1 - g.seat]],
    pot: o.pot,
    call: o.bet.call,
    min: o.bet.min,
    paid: o.bet.paid[g.seat],
    offers: o.me.gearOffers,
  });
}
mkdirSync("reports", { recursive: true });
writeFileSync(file, JSON.stringify(games));
if (command === "report") {
  const report = games.map((g) => {
    const t = replay(g);
    return {
      id: g.id,
      modelSeat: g.seat,
      complete: !!t.result,
      result: t.result,
      stacks: t.stacks,
      fees: t.spent,
      modelDecisions: g.model.length,
      modelBets: g.model
        .filter((m) => m.observation.phase === "bet")
        .map((m) => ({
          round: m.observation.round,
          action: m.action,
          probability: m.probability,
          reason: m.reason,
        })),
      ...(t.result ? { revealed: t.units } : {}),
    };
  });
  writeFileSync(
    "reports/intent-v4-model-5.json",
    JSON.stringify(report, null, 2),
  );
  console.log(JSON.stringify({ complete, report }));
} else console.log(JSON.stringify({ complete, pending: visible }));
