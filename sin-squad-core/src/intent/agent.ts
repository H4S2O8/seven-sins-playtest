import { Rng } from "../rng.js";
import { battle } from "./battle.js";
import { CARDS, GEARS, card, plans, validPlan } from "./content.js";
import { tier } from "./table.js";
import {
  OFF,
  type Action,
  type Observation,
  type Plan,
  type Unit,
} from "./types.js";
import { equipmentFit } from "./information.js";

export const PERMS = [
  [0, 1, 2],
  [0, 2, 1],
  [1, 0, 2],
  [1, 2, 0],
  [2, 0, 1],
  [2, 1, 0],
];
export interface Forecast {
  win: number;
  tie: number;
  lanes: number[];
  tiers: number[][];
  samples: number;
  score: number;
}
export interface Decision {
  action: Action;
  forecast?: Forecast;
  reason: string;
}
const clamp = (n: number, a: number, b: number) => Math.max(a, Math.min(b, n));
const activeFields = (o: Observation) =>
  o.effects.filter((e) => e.active).map((e) => e.id!);
function hash(text: string) {
  let h = 2166136261;
  for (const ch of text) h = Math.imul(h ^ ch.charCodeAt(0), 16777619);
  return h >>> 0;
}
const producers = new Set([
  "WR2",
  "WR3",
  "GR1",
  "GR2",
  "GR3",
  "GL2",
  "EN2",
  "SL2",
  "WR4",
  "GR4",
  "GL5",
]);
const support = new Set([
  "WR2",
  "GR2",
  "GL2",
  "GL3",
  "LU2",
  "LU3",
  "SL4",
  "LU4",
  "LU5",
]);
function affinity(id: string, g: string | null) {
  if (!g) return 1;
  if (["G01", "G08", "G12", "G15", "G17", "G23"].includes(g))
    return producers.has(id) ? 3 : 1;
  if (["G03", "G09", "G22", "G24"].includes(g)) return support.has(id) ? 1 : 2;
  if (["G04", "G05", "G10", "G14", "G18"].includes(g))
    return ["WR4", "SL4", "LU4", "LU5"].includes(id) ? 3 : 1;
  return 1;
}
/** The only input is an observation. Neither game state nor the deal seed is accepted. */
export function hypotheses(
  o: Observation,
  n = 16,
  signals = true,
  equipment = true,
  salt = 0,
): Unit[][] {
  const rng = new Rng(
    hash(JSON.stringify([o.foe.tiers, activeFields(o), salt])),
  );
  const out: Unit[][] = [];
  for (let k = 0; k < (equipment ? n * 3 : n); k++) {
    const nums = o.foe.tiers.map((t) =>
      t === 0 ? 3 + rng.int(3) : t === 1 ? 6 + rng.int(2) : 8 + rng.int(3),
    );
    // No raw-number arena exists: all numeric orders remain possible a priori.
    const layout = rng.pick(PERMS);
    const team = layout.map((i, p) => {
      const sig =
        signals && !["draft", "place", "initial-plan"].includes(o.phase)
          ? o.foe.signals[p]
          : undefined;
      const g = equipment ? o.foe.equipment[p] : null;
      const candidates = CARDS.filter(
        (c) =>
          !sig ||
          !sig.on ||
          (c.mark === sig.kind &&
            validPlan(c.id, p, { on: true, targets: sig.targets, mode: 0 })),
      );
      if (!candidates.length)
        throw Error("No hypothesis satisfies public signal");
      const weighted = candidates.flatMap((c) =>
        Array.from({ length: affinity(c.id, g) }, () => c),
      );
      const c = rng.pick(weighted);
      const available = plans(c.id, p);
      const plan: Plan = sig
        ? sig.on
          ? {
              on: true,
              targets: structuredClone(sig.targets),
              mode: c.modes ? (rng.int(2) as 0 | 1) : 0,
            }
          : OFF()
        : rng.next() < 0.15
          ? OFF()
          : rng.pick(available.filter((x) => x.on));
      return { id: c.id, raw: nums[i], gear: g, plan };
    });
    out.push(team);
  }
  if (!equipment) return out;
  const weights = out.map(equipmentFit),
    total = weights.reduce((a, b) => a + b, 0);
  return Array.from({ length: n }, () => {
    let v = rng.next() * total;
    for (let i = 0; i < out.length; i++) {
      v -= weights[i];
      if (v <= 0) return out[i];
    }
    return out[out.length - 1];
  });
}
export function layoutPrior(p: number[]) {
  const sorted = p.slice().sort((a, b) => a - b);
  return sorted[1] * 1.1 + sorted[2] * 0.8 + sorted[0] * 0.3;
}
export function forecast(
  o: Observation,
  own: Unit[],
  worlds = hypotheses(o),
  fields = activeFields(o),
): Forecast {
  let wins = 0,
    ties = 0,
    score = 0;
  const lanes = [0, 0, 0],
    tiers = [
      [0, 0, 0],
      [0, 0, 0],
      [0, 0, 0],
    ];
  for (const foe of worlds) {
    const b = battle([own, foe], fields, {
      trace: false,
      initiative: o.initiative === o.seat ? 0 : 1,
    });
    wins += b.winner === 0 ? 1 : 0;
    ties += b.winner === null ? 1 : 0;
    score += b.winner === 0 ? 3 : b.winner === null ? 0 : -3;
    b.lanes.forEach((w, p) => {
      lanes[p] += w === 0 ? 1 : w === null ? 0.5 : 0;
      score += w === 0 ? 0.4 : w === 1 ? -0.4 : 0;
      score += 0.02 * clamp(b.powers[0][p] - b.powers[1][p], -6, 6);
      tiers[p][tier(foe[p].raw)]++;
    });
  }
  return {
    win: wins / worlds.length,
    tie: ties / worlds.length,
    lanes: lanes.map((v) => v / worlds.length),
    tiers: tiers.map((row) => row.map((v) => v / worlds.length)),
    samples: worlds.length,
    score: score / worlds.length,
  };
}
export function optimise(
  o: Observation,
  start: Unit[],
  worlds: Unit[][],
  passes = 1,
): Unit[] {
  const own = structuredClone(start);
  let best = forecast(o, own, worlds).score;
  for (let pass = 0; pass < passes; pass++)
    for (let p = 0; p < 3; p++) {
      let selected = own[p].plan;
      for (const plan of plans(own[p].id, p)) {
        own[p].plan = plan;
        const score = forecast(o, own, worlds).score;
        if (score > best + 1e-7) {
          best = score;
          selected = plan;
        }
      }
      own[p].plan = selected;
    }
  return own;
}
function initial(id: string, p: number): Plan {
  const list = plans(id, p).filter((a) => a.on);
  // Deterministic seed plan only; exact resolver search can turn it off or redirect it.
  return (
    list.find((a) => a.targets.every((t) => t.pos !== p)) || list[0] || OFF()
  );
}
export class Bot {
  rng: Rng;
  constructor(
    seed: number,
    readonly style: "balanced" | "cautious" | "pressure" = "balanced",
  ) {
    this.rng = new Rng(seed);
  }
  decide(o: Observation): Decision {
    const worlds = hypotheses(o, 4),
      s = o.seat,
      op = 1 - s;
    if (o.phase === "draft") {
      // Evaluate sampled candidate sets by actual effects, not merely by complexity or rarity.
      let score = -Infinity,
        indices = [0, 1, 2];
      for (let k = 0; k < 14; k++) {
        const ids = this.rng.sample(
          Array.from({ length: 9 }, (_, i) => i),
          3,
        );
        const own = ids.map((i, p) => ({
          id: o.me.offer[i],
          raw: o.me.numbers[p],
          gear: null,
          plan: initial(o.me.offer[i], p),
        }));
        const v = forecast(o, own, worlds).score;
        if (v > score) {
          score = v;
          indices = ids;
        }
      }
      return {
        action: { type: "draft", indices },
        reason: "在候选组合中用实际结算选择三人；同名人物保留独立实例",
      };
    }
    if (o.phase === "place") {
      const candidates: {
        units: number[];
        numbers: number[];
        own: Unit[];
        value: number;
      }[] = [];
      for (const units of PERMS)
        for (const numbers of PERMS) {
          const own = units.map((i, p) => ({
            id: o.me.kept[i],
            raw: o.me.numbers[numbers[p]],
            gear: null,
            plan: initial(o.me.kept[i], p),
          }));
          candidates.push({
            units,
            numbers,
            own,
            value: forecast(o, own, worlds).score,
          });
        }
      candidates.sort((a, b) => b.value - a.value);
      const best = candidates
        .map((c) => ({
          ...c,
          value: forecast(o, optimise(o, c.own, worlds), worlds).score,
        }))
        .sort((a, b) => b.value - a.value)[0];
      return {
        action: { type: "place", units: best.units, numbers: best.numbers },
        reason: "全部36种人物与数字排位均优化技能，避免提前淘汰需要配合的布局",
      };
    }
    const own = o.me.units!;
    if (o.phase === "initial-plan" || o.phase === "plan") {
      const selected = optimise(o, own, worlds, 2);
      return {
        action: { type: "plan", plans: selected.map((u) => u.plan) },
        forecast: forecast(o, selected, hypotheses(o, 16)),
        reason: "有限信念样本下两轮坐标搜索；公开目标约束对手范围",
      };
    }
    if (o.phase === "operate") {
      const empty = [0, 1, 2].filter((p) => !own[p].gear);
      const base = forecast(o, own, worlds);
      if (o.me.gearOffers.length) {
        const choices: {
          offer: number;
          pos: number;
          own: Unit[];
          value: number;
        }[] = [];
        o.me.gearOffers.forEach((g, offer) =>
          empty.forEach((pos) => {
            const team = structuredClone(own);
            team[pos].gear = g;
            choices.push({
              offer,
              pos,
              own: team,
              value: forecast(o, team, worlds).score,
            });
          }),
        );
        choices.sort((a, b) => b.value - a.value);
        const best = choices
          .slice(0, 2)
          .map((c) => ({
            ...c,
            value: forecast(o, optimise(o, c.own, worlds), worlds).score,
          }))
          .sort((a, b) => b.value - a.value)[0];
        return {
          action: { type: "equip", offer: best.offer, pos: best.pos },
          reason: "已经付费，必须在合法空位选装；比较重设技能后的结果",
        };
      }
      if (!empty.length || o.stacks[s] <= 2)
        return {
          action: { type: "operate", buy: false },
          reason: "没有空位或可用筹码",
        };
      let improved = 0;
      for (let sample = 0; sample < 4; sample++) {
        let best = -Infinity;
        for (const g of this.rng.sample(GEARS, 3))
          for (const p of empty) {
            const team = structuredClone(own);
            team[p].gear = g.id;
            const v = forecast(o, team, worlds);
            best = Math.max(best, v.win + v.tie / 2);
          }
        improved += best - (base.win + base.tie / 2);
      }
      const value = (improved / 4) * Math.max(24, o.pot);
      return {
        action: { type: "operate", buy: value > 2.1 && base.win < 0.94 },
        forecast: base,
        reason: `未知装备的抽样增益价值${value.toFixed(2)}，与2筹码比较`,
      };
    }
    if (o.phase === "bid") {
      const effect = o.effects[o.round].id!,
        base = forecast(o, own, worlds),
        withEffect = forecast(o, own, worlds, [effect]);
      const diff = withEffect.score - base.score;
      return {
        action: {
          type: "bid",
          yes: diff > 0,
          amount: Math.min(
            Math.max(0, Math.floor(o.stacks[s] - 1)),
            6,
            Math.max(0, Math.floor(Math.abs(diff) * 1.2)),
          ),
        },
        reason: "比较新场地替换旧场地的收益；平价保留当前场地",
      };
    }
    if (o.phase === "bet") {
      const pred = forecast(o, own, hypotheses(o, 24));
      const pressure = o.history.filter(
        (h) => h.seat === op && h.type === "raise",
      ).length;
      // Uncalibrated belief samples are not 24 independent observations of a real opponent.
      // Shrink toward uncertainty, especially before the equipment/intent windows close.
      const trust = o.round <= 1 ? 0.55 : o.round <= 3 ? 0.65 : 0.75;
      const p = clamp(
        0.5 +
          (pred.win + pred.tie / 2 - 0.5) * trust -
          Math.min(0.18, pressure * 0.04),
        0.02,
        0.98,
      );
      const need = Math.min(o.bet.call, o.stacks[s]),
        odds = need / (o.pot + need);
      const risk =
        this.style === "cautious"
          ? 0.09
          : this.style === "pressure"
            ? 0.01
            : 0.05;
      if (need > 0 && p < odds + risk)
        return {
          action: { type: "fold" },
          forecast: pred,
          reason: `继续胜率${p.toFixed(2)}低于底池赔率加风险${(odds + risk).toFixed(2)}`,
        };
      const bluff =
        pressure === 0 &&
        p < 0.38 &&
        this.rng.next() < (this.style === "pressure" ? 0.12 : 0.025);
      const threshold =
        this.style === "pressure"
          ? 0.61
          : this.style === "cautious"
            ? 0.76
            : 0.68;
      const all = o.bet.paid[s] + o.stacks[s];
      if ((p > threshold || bluff) && o.stacks[op] > 0 && all > o.bet.target) {
        const size = Math.max(2, Math.floor(o.pot * (p > 0.84 ? 0.8 : 0.45))),
          to = Math.min(all, Math.max(o.bet.min, o.bet.target + size));
        return {
          action: { type: "raise", to },
          forecast: pred,
          reason: bluff
            ? "有限诈唬，利用公开信号施压"
            : "价值下注，按底池大小投入",
        };
      }
      return {
        action: need > 0 ? { type: "call" } : { type: "check" },
        forecast: pred,
        reason:
          need > 0
            ? "继续成本在估计胜率可承受范围内"
            : "保留筹码，等待装备与公开意图",
      };
    }
    throw Error("Unhandled observation phase " + o.phase);
  }
}
