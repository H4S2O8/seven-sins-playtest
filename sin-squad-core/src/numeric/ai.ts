import { Rng } from "../rng.js";
import {
  NUMERIC_CHARACTER_IDS,
  NUMERIC_EQUIPMENT,
  characterById,
  runNumericResolution,
  type NumericSlot,
  type NumericStats,
} from "./content.js";
import type { NumericAction, NumericObservation } from "./types.js";

export type NumericStyle = "cautious" | "aggressive" | "bluff";
export type DecisionState =
  | "drafting"
  | "rebuilding"
  | "positioning"
  | "value"
  | "probing"
  | "bluffing"
  | "defending"
  | "folding"
  | "checking"
  | "equipping"
  | "voting"
  | "bidding";
const profiles = {
  cautious: {
    value: 0.69,
    bluff: 0.025,
    tolerance: 0.01,
    sizing: 0.45,
    bid: 8,
  },
  aggressive: {
    value: 0.56,
    bluff: 0.14,
    tolerance: 0.1,
    sizing: 0.8,
    bid: 14,
  },
  bluff: { value: 0.64, bluff: 0.28, tolerance: 0.06, sizing: 1.0, bid: 12 },
};
const perms = [
  [0, 1, 2],
  [0, 2, 1],
  [1, 0, 2],
  [1, 2, 0],
  [2, 0, 1],
  [2, 1, 0],
] as const;
const clone = (team: NumericSlot[]) =>
  team.map((x) => ({ ...x, equipment: x.equipment && { ...x.equipment } }));
type Plan = {
  ids: string[];
  numbers: number[];
  value: number;
  redraw: boolean;
};
export interface AgentSave {
  style: NumericStyle;
  rng: number;
  hand: number;
  plan: Plan | null;
  state: DecisionState;
  samples: number;
}

/** No Table reference: the policy can only see its own legal observation. */
export class NumericAgent {
  private rng: Rng;
  private hand = -1;
  private plan: Plan | null = null;
  state: DecisionState = "drafting";
  constructor(
    readonly style: NumericStyle,
    seed: number,
    private readonly samples = 6,
  ) {
    this.rng = new Rng(seed);
  }
  save(): AgentSave {
    return structuredClone({
      style: this.style,
      rng: this.rng.snapshot(),
      hand: this.hand,
      plan: this.plan,
      state: this.state,
      samples: this.samples,
    });
  }
  static restore(s: AgentSave) {
    if (
      !(s.style in profiles) ||
      !Number.isInteger(s.rng) ||
      !Number.isInteger(s.samples) ||
      s.samples < 1 ||
      s.samples > 32
    )
      throw Error("无效的电脑存档");
    const a = new NumericAgent(s.style, s.rng, s.samples);
    a.rng = Rng.restore(s.rng);
    a.hand = s.hand;
    a.plan = structuredClone(s.plan);
    a.state = s.state;
    return a;
  }

  /** Soft evidence, never a hard reveal: an opponent may bluff or have poor offers. */
  private evidence(team: NumericSlot[], o: NumericObservation) {
    const ns = team.map((x) => x.number);
    let weight = 1;
    team.forEach((slot, i) => {
      const id = slot.equipment?.id,
        n = slot.number;
      let plausible: boolean | null = null;
      if (id === "E02") plausible = n <= 4;
      if (id === "E08") plausible = n >= 8;
      if (id === "E16") plausible = n === Math.min(...ns);
      if (id === "E17") plausible = n === Math.max(...ns);
      if (id === "E23") plausible = n > Math.min(...ns) && n < Math.max(...ns);
      if (id === "E20" && o.arenaId !== "NA05")
        plausible = slot.effectId === "LU2" || team[i + 1]?.effectId === "GL2";
      if (plausible !== null) weight *= plausible ? 1.8 : 0.7;
      // Broad equipment has a useful floor: only weak evidence of a particular plan.
      const support = team.some(
        (x, j) =>
          j !== i && ["LU1", "LU4", "LU5", "PR3", "SL3"].includes(x.effectId),
      );
      if (id === "E14") weight *= support ? 1.6 : 0.85;
      if (id === "E18")
        weight *=
          support ||
          ["WR2", "GR1", "GR2", "SL1", "SL2", "EN2", "PR2"].includes(
            slot.effectId,
          )
            ? 1.5
            : 0.9;
      if (id === "E20")
        weight *= characterById(slot.effectId).keywords?.some(
          (k) => k.kind === "legacy",
        )
          ? 1.4
          : 1;
      const kinds = team
        .filter((_, j) => j !== i)
        .flatMap((x) => characterById(x.effectId).keywords ?? [])
        .map((k) => k.kind);
      if (id === "E03" || id === "E19")
        weight *= new Set(kinds).size >= 2 ? 1.5 : 0.85;
      if (id === "E15")
        weight *= kinds.some((k) => k === "ward" || k === "guard") ? 1.7 : 0.8;
      if (id === "E05")
        weight *= Boolean(
          characterById(slot.effectId).keywords?.some((k) => k.kind !== "link"),
        )
          ? 1.5
          : 0.85;
    });
    return weight;
  }
  hypotheses(o: NumericObservation, count = this.samples): NumericSlot[][] {
    const pool: { team: NumericSlot[]; weight: number }[] = [];
    for (let k = 0; k < count * 5; k++) {
      const tiers = this.rng.shuffle(o.opponent.tiers),
        ids = Array.from({ length: 3 }, () =>
          this.rng.pick(NUMERIC_CHARACTER_IDS),
        );
      const team: NumericSlot[] = tiers.map((tier, i) => ({
        number:
          tier === "低"
            ? 3 + this.rng.int(2)
            : tier === "高"
              ? 8 + this.rng.int(3)
              : 5 + this.rng.int(3),
        effectId: ids[i],
        equipment: o.opponent.equipment[i]
          ? {
              ...o.opponent.equipment[i]!,
              tier: o.opponent.equipment[i]!.tier as "normal",
            }
          : null,
      }));
      pool.push({ team, weight: this.evidence(team, o) });
    }
    const sum = pool.reduce((a, x) => a + x.weight, 0);
    return Array.from({ length: count }, () => {
      let at = this.rng.next() * sum;
      for (const x of pool) {
        at -= x.weight;
        if (at <= 0) return x.team;
      }
      return pool[pool.length - 1].team;
    });
  }
  private team(o: NumericObservation): NumericSlot[] {
    return o.me.slots!.map((x, i) => ({
      ...x,
      equipment: o.me.equipment[i]
        ? { ...o.me.equipment[i]!, tier: o.me.equipment[i]!.tier as "normal" }
        : null,
    }));
  }
  private stats(
    o: NumericObservation,
    future: boolean,
  ): [NumericStats, NumericStats] {
    const rows = [o.publicStats[o.seat], o.publicStats[1 - o.seat]].map(
      (x) => ({ ...x }),
    );
    if (future)
      for (const x of rows) {
        x.checks = 3;
        x.opsPaid = 2;
        x.round = 4;
        x.invested = Math.max(x.invested ?? 0, 8);
      }
    return rows as [NumericStats, NumericStats];
  }
  private assess(
    o: NumericObservation,
    team: NumericSlot[],
    foes: NumericSlot[][],
    effects = o.effects.filter((x) => x.status === "active").map((x) => x.id),
    future = false,
  ) {
    let wins = 0,
      margin = 0;
    for (const foe of foes) {
      const r = runNumericResolution({
        teams: [team, foe],
        arenaId: o.arenaId!,
        ruleId: o.ruleId!,
        activeEffectIds: effects,
        stats: this.stats(o, future),
        recordTrace: false,
      });
      wins += r.winner === null ? 0.5 : r.winner === 0 ? 1 : 0;
      margin +=
        r.powers[0].reduce((a, b) => a + b, 0) -
        r.powers[1].reduce((a, b) => a + b, 0);
    }
    return {
      equity: wins / foes.length,
      rank:
        wins / foes.length +
        Math.max(-0.09, Math.min(0.09, margin / foes.length / 200)),
    };
  }
  private draft(o: NumericObservation, foes: NumericSlot[][]): NumericAction {
    this.state = "drafting";
    if (this.plan?.redraw && o.me.kept.length === 1 && !o.me.rerolled) {
      this.state = "rebuilding";
      this.plan = null;
      return { type: "reroll" };
    }
    const count = (xs: string[], id: string) =>
      xs.filter((x) => x === id).length;
    if (
      !this.plan ||
      this.plan.ids.some(
        (id) =>
          count(this.plan!.ids, id) >
          count([...o.me.kept, ...o.me.current], id),
      )
    ) {
      let best: Plan | null = null;
      for (let k = 0; k < 48; k++) {
        const ids = this.rng.shuffle([
          ...o.me.kept,
          ...this.rng.sample(o.me.current, 3 - o.me.kept.length),
        ]);
        const numbers = [...this.rng.pick(perms)];
        const team = ids.map((effectId, i) => ({
          effectId,
          number: o.me.numbers[numbers[i]],
          equipment: null,
        }));
        const score = this.assess(o, team, foes, undefined, true).rank;
        if (!best || score > best.value)
          best = { ids, numbers, value: score, redraw: false };
      }
      best!.redraw =
        !o.me.rerolled && o.me.kept.length === 0 && best!.value < 0.48;
      this.plan = best;
    }
    return {
      type: "keep",
      index: o.me.current.indexOf(
        this.plan!.ids.find(
          (id) => count(this.plan!.ids, id) > count(o.me.kept, id),
        )!,
      ),
    };
  }
  act(o: NumericObservation): NumericAction | null {
    if (!o.toAct.includes(o.seat)) return null;
    if (this.hand !== o.handNo) {
      this.hand = o.handNo;
      this.plan = null;
    }
    const foes = this.hypotheses(o);
    if (o.phase === "draft") return this.draft(o, foes);
    if (o.phase === "place") {
      this.state = "positioning";
      let best = -Infinity,
        action: NumericAction = {
          type: "place",
          numbers: [0, 1, 2],
          effects: [0, 1, 2],
        };
      for (const numbers of perms)
        for (const effects of perms) {
          const team = effects.map((e, i) => ({
            effectId: o.me.kept[e],
            number: o.me.numbers[numbers[i]],
            equipment: null,
          }));
          const score = this.assess(o, team, foes, undefined, true).rank;
          if (score > best) {
            best = score;
            action = {
              type: "place",
              numbers: [...numbers],
              effects: [...effects],
            };
          }
        }
      return action;
    }
    if (!o.me.slots) return null;
    const team = this.team(o),
      base = this.assess(o, team, foes),
      profile = profiles[this.style];
    if (o.phase === "bet") {
      const stack = o.stacks[o.seat],
        call = Math.min(o.betting.toCall, stack);
      const odds = call / Math.max(1, o.pot + call);
      // A small sample is uncertain; shrink estimates away from 0/1.
      const equity = (base.equity * this.samples + 1) / (this.samples + 2);
      if (
        call &&
        equity + profile.tolerance <
          odds + (this.style === "cautious" ? 0.1 : 0.02)
      ) {
        this.state = "folding";
        return { type: "fold" };
      }
      const publicRaises = o.publicStats[o.seat].betOrRaise ?? 0;
      const bluff =
        equity > 0.22 && equity < 0.57 && this.rng.next() < profile.bluff;
      const value = equity >= profile.value;
      if (stack > call && publicRaises < 2 && (value || bluff)) {
        this.state = bluff ? "bluffing" : call ? "value" : "probing";
        const effective = Math.min(
          stack,
          o.stacks[1 - o.seat] + o.betting.toCall,
        );
        const amount = Math.max(
          o.betting.minRaiseTo,
          o.betting.target + Math.round(Math.max(4, o.pot) * profile.sizing),
        );
        const to = Math.min(o.betting.roundBet[o.seat] + effective, amount);
        if (
          to >= o.betting.minRaiseTo &&
          to - o.betting.roundBet[o.seat] <= stack
        )
          return o.betting.target
            ? { type: "raise", to }
            : { type: "bet", amount: to };
      }
      this.state = call ? "defending" : "checking";
      return call ? { type: "call" } : { type: "check" };
    }
    if (o.phase === "operate" || o.phase === "equip") {
      this.state = "equipping";
      const tier =
        o.round <= 3 ? "normal" : o.round <= 5 ? "replace-1" : "replace-2";
      const ids =
        o.phase === "equip"
          ? o.me.offers!
          : this.rng.sample(
              NUMERIC_EQUIPMENT.map((x) => x.id),
              6,
            );
      let best = base.rank,
        pick = { offerIndex: 0, pos: 0 };
      ids.forEach((id, offerIndex) =>
        team.forEach((slot, pos) => {
          if (o.round <= 3 && slot.equipment) return;
          const trial = clone(team);
          trial[pos].equipment = { id, tier };
          const score = this.assess(o, trial, foes).rank;
          if (score > best) {
            best = score;
            pick = { offerIndex, pos };
          }
        }),
      );
      if (o.phase === "equip")
        return best > base.rank + 0.001
          ? { type: "equip", ...pick }
          : { type: "operate", draft: false };
      const price = o.opFee / Math.max(8, o.pot + o.opFee);
      return {
        type: "operate",
        draft: o.canEquip && best - base.rank > Math.max(0.018, price * 0.22),
      };
    }
    if (o.phase === "vote" || o.phase === "bid") {
      const effect = o.effects[o.round - 1].id,
        active = o.effects
          .filter((x) => x.status === "active")
          .map((x) => x.id);
      const gain =
        this.assess(o, team, foes, [...active, effect]).rank -
        this.assess(o, team, foes, active).rank;
      if (o.phase === "vote") {
        this.state = "voting";
        return { type: "vote", activate: gain > 0.005 };
      }
      this.state = "bidding";
      return {
        type: "bid",
        amount: Math.min(
          o.bidCap,
          Math.floor(Math.abs(gain) * Math.min(profile.bid, o.pot * 0.45)),
        ),
      };
    }
    return null;
  }
}
