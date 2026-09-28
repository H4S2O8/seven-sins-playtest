import { Rng } from "../rng.js";
import { CARDS, FIELDS, GEARS, signal, validPlan } from "./content.js";
import { battle } from "./battle.js";
import {
  OFF,
  type Action,
  type Observation,
  type Plan,
  type Seat,
  type Unit,
} from "./types.js";

export const tier = (n: number) => (n <= 5 ? 0 : n <= 7 ? 1 : 2);
export class IntentTable {
  readonly rng: Rng;
  phase = "draft";
  round = 1;
  effects: { id: string; active: boolean | null }[];
  revealedEffects = 1;
  numbers: [number[], number[]];
  offers: [string[], string[]];
  kept: [string[], string[]] = [[], []];
  units: [Unit[] | null, Unit[] | null] = [null, null];
  redrawn = [false, false];
  equipment: [(string | null)[], (string | null)[]] = [
    [null, null, null],
    [null, null, null],
  ];
  plans: [Plan[] | null, Plan[] | null] = [null, null];
  ready = [false, false];
  gearOffers: [string[], string[]] = [[], []];
  bought = [false, false];
  votes: (boolean | null)[] = [null, null];
  bids: (number | null)[] = [null, null];
  stacks: [number, number] = [98, 98];
  pot = 4;
  spent = 0;
  paid: [number, number] = [0, 0];
  target = 0;
  lastRaise = 2;
  acted = [false, false];
  turn: Seat;
  readonly initiative: Seat;
  history: Observation["history"] = [];
  result: Observation["result"] = null;
  private initialTotal = 200;
  constructor(
    seed: number,
    initiative: Seat = (seed % 2) as Seat,
    startingStacks: [number, number] = [100, 100],
  ) {
    if (
      startingStacks.some(
        (n) => !Number.isFinite(n) || n <= 0 || !Number.isInteger(n * 2),
      )
    )
      throw Error("Invalid starting stacks");
    const ante = Math.min(2, ...startingStacks);
    this.stacks = startingStacks.map((n) => n - ante) as [number, number];
    this.pot = 2 * ante;
    this.initialTotal = startingStacks[0] + startingStacks[1];
    this.rng = new Rng(seed);
    this.rng.int(2); // Preserve deal streams from the initial lab protocol.
    this.turn = initiative;
    this.initiative = initiative;
    this.effects = this.rng
      .sample(FIELDS, 4)
      .map((e, i) => ({ id: e.id, active: i === 0 ? true : null }));
    this.numbers = [this.drawNumbers(), this.drawNumbers()];
    this.offers = [this.drawOffer(), this.drawOffer()];
  }
  private drawNumbers() {
    return Array.from({ length: 3 }, () => 3 + this.rng.int(8));
  }
  private drawOffer() {
    return Array.from({ length: 9 }, () => this.rng.pick(CARDS).id);
  }
  actors(): Seat[] {
    if (this.result) return [];
    if (this.phase === "bet") return [this.turn];
    return ([0, 1] as Seat[]).filter((s) => !this.ready[s]);
  }
  observe(s: Seat): Observation {
    const op = (1 - s) as Seat;
    return structuredClone({
      seat: s,
      initiative: this.initiative,
      seedLabel: 0,
      phase: this.phase,
      round: this.round,
      actor: this.actors(),
      effects: this.effects.map((e, i) =>
        i < this.revealedEffects ? e : { id: null, active: null },
      ),
      me: {
        numbers: this.numbers[s],
        offer: this.offers[s],
        kept: this.kept[s],
        units: this.units[s],
        gearOffers: this.gearOffers[s],
        redrawn: this.redrawn[s],
      },
      foe: {
        tiers: this.numbers[op].map(tier).sort(),
        equipment: this.equipment[op],
        signals: this.units[op]?.map(signal) || [],
      },
      pot: this.pot,
      stacks: this.stacks,
      bet: {
        call: Math.max(0, this.target - this.paid[s]),
        min: this.target + this.lastRaise,
        paid: this.paid,
        target: this.target,
      },
      history: this.history,
      result: this.result,
    });
  }
  private setPhase(phase: string) {
    this.phase = phase;
    this.ready = [false, false];
  }
  private startBet() {
    this.setPhase("bet");
    this.paid = [0, 0];
    this.target = 0;
    this.lastRaise = 2;
    this.acted = [false, false];
    this.turn = (1 - this.turn) as Seat;
    if (this.stacks.some((n) => n === 0)) this.finish(null, false);
  }
  private finish(winner: Seat | null, fold: boolean) {
    // Heads-up unmatched contribution is returned before distributing the contested pot.
    const excess = Math.abs(this.paid[0] - this.paid[1]);
    if (excess) {
      const s = this.paid[0] > this.paid[1] ? 0 : 1;
      this.stacks[s] += excess;
      this.pot -= excess;
      this.paid[s] -= excess;
    }
    const resolved = fold
      ? null
      : battle(
          this.units as [Unit[], Unit[]],
          this.effects.filter((e) => e.active).map((e) => e.id),
          { initiative: this.initiative },
        );
    if (resolved) winner = resolved.winner;
    const payouts: [number, number] =
      winner === null
        ? [this.pot / 2, this.pot / 2]
        : winner === 0
          ? [this.pot, 0]
          : [0, this.pot];
    this.stacks[0] += payouts[0];
    this.stacks[1] += payouts[1];
    this.pot = 0;
    this.result = {
      winner,
      fold,
      battle: resolved,
      payouts,
      ...(!fold
        ? { teams: structuredClone(this.units as [Unit[], Unit[]]) }
        : {}),
    };
    this.phase = "done";
    if (
      Math.abs(
        this.stacks[0] + this.stacks[1] + this.spent - this.initialTotal,
      ) > 1e-8
    )
      throw Error("Chip conservation failed");
  }
  private closeBet() {
    if (
      this.stacks.some((n) => n === 0) ||
      (this.round >= 4 && this.target === 0)
    ) {
      this.finish(null, false);
      return;
    }
    if (this.round <= 3) {
      this.gearOffers = [[], []];
      this.bought = [false, false];
      this.setPhase("operate");
    } else {
      this.round++;
      this.startBet();
    }
  }
  private both() {
    return this.ready.every(Boolean);
  }
  act(s: Seat, a: Action) {
    if (!this.actors().includes(s)) throw Error("Not an eligible actor");
    const op = (1 - s) as Seat;
    const perm = (v: number[]) =>
      v.length === 3 && [...v].sort().join(",") === "0,1,2";
    if (this.phase === "draft") {
      if (a.type === "redraw") {
        if (this.redrawn[s]) throw Error("Already redrawn");
        this.redrawn[s] = true;
        this.offers[s] = this.drawOffer();
      } else if (
        a.type === "draft" &&
        a.indices.length === 3 &&
        new Set(a.indices).size === 3 &&
        a.indices.every((i) => Number.isInteger(i) && i >= 0 && i < 9)
      ) {
        this.kept[s] = a.indices.map((i) => this.offers[s][i]);
        this.ready[s] = true;
        if (this.both()) this.setPhase("place");
      } else throw Error("Invalid draft");
    } else if (this.phase === "place") {
      if (a.type !== "place" || !perm(a.units) || !perm(a.numbers))
        throw Error("Invalid placement");
      this.units[s] = a.units.map((i, p) => ({
        id: this.kept[s][i],
        raw: this.numbers[s][a.numbers[p]],
        gear: null,
        plan: OFF(),
      }));
      this.ready[s] = true;
      if (this.both()) this.setPhase("initial-plan");
    } else if (this.phase === "plan" || this.phase === "initial-plan") {
      if (
        a.type !== "plan" ||
        a.plans.length !== 3 ||
        !a.plans.every((p, i) => validPlan(this.units[s]![i].id, i, p))
      )
        throw Error("Invalid plan");
      if (this.round > 3) throw Error("Configuration locked");
      this.plans[s] = structuredClone(a.plans);
      this.ready[s] = true;
      if (this.both()) {
        for (const seat of [0, 1] as Seat[])
          this.units[seat]!.forEach((u, i) => (u.plan = this.plans[seat]![i]));
        if (this.phase === "plan") this.round++;
        this.plans = [null, null];
        this.startBet();
      }
    } else if (this.phase === "operate") {
      if (a.type === "operate" && !this.bought[s]) {
        if (a.buy) {
          if (
            this.stacks[s] <= 2 ||
            this.round > 3 ||
            this.units[s]!.every((u) => u.gear)
          )
            throw Error("Cannot buy");
          this.stacks[s] -= 2;
          this.spent += 2;
          this.bought[s] = true;
          this.gearOffers[s] = this.rng.sample(GEARS, 3).map((g) => g.id);
        } else this.ready[s] = true;
      } else if (
        a.type === "equip" &&
        this.bought[s] &&
        this.gearOffers[s].length
      ) {
        if (
          !Number.isInteger(a.offer) ||
          a.offer < 0 ||
          a.offer >= 3 ||
          !Number.isInteger(a.pos) ||
          a.pos < 0 ||
          a.pos >= 3 ||
          this.units[s]![a.pos].gear
        )
          throw Error("Invalid compulsory equipment");
        this.units[s]![a.pos].gear = this.gearOffers[s][a.offer];
        this.gearOffers[s] = [];
        this.ready[s] = true;
      } else
        throw Error(
          "Paying requires installation; skipping/replacing not allowed",
        );
      if (this.both()) {
        this.equipment = this.units.map((t) =>
          t!.map((u) => u.gear),
        ) as typeof this.equipment;
        this.revealedEffects = this.round + 1;
        this.votes = [null, null];
        this.bids = [null, null];
        this.setPhase("bid");
      }
    } else if (this.phase === "bid") {
      if (
        a.type !== "bid" ||
        typeof a.yes !== "boolean" ||
        !Number.isInteger(a.amount) ||
        a.amount < 0 ||
        a.amount > Math.max(0, Math.min(6, Math.floor(this.stacks[s] - 1)))
      )
        throw Error("Invalid sealed bid");
      this.bids[s] = a.amount;
      this.votes[s] = a.yes;
      this.ready[s] = true;
      if (this.both()) {
        for (const seat of [0, 1] as Seat[]) {
          this.stacks[seat] -= this.bids[seat]!;
          this.pot += this.bids[seat]!;
        }
        const replace =
          this.bids[0] !== this.bids[1] &&
          this.votes[this.bids[0]! > this.bids[1]! ? 0 : 1] === true;
        if (replace)
          this.effects.forEach((e) => {
            if (e.active) e.active = false;
          });
        this.effects[this.round].active = replace;
        this.setPhase("plan");
      }
    } else if (this.phase === "bet") {
      const need = this.target - this.paid[s];
      if (a.type === "fold") this.finish(op, true);
      else if (
        (a.type === "check" && need === 0) ||
        (a.type === "call" && need > 0)
      ) {
        const n = Math.min(need, this.stacks[s]);
        this.stacks[s] -= n;
        this.pot += n;
        this.paid[s] += n;
        this.acted[s] = true;
        if (this.acted[op]) this.closeBet();
        else this.turn = op;
      } else if (a.type === "raise") {
        const all = this.paid[s] + this.stacks[s];
        if (
          !Number.isInteger(a.to * 2) ||
          a.to <= this.target ||
          a.to > all ||
          (a.to < this.target + this.lastRaise && a.to !== all) ||
          this.stacks[op] === 0
        )
          throw Error("Invalid raise");
        const n = a.to - this.paid[s],
          inc = a.to - this.target;
        this.stacks[s] -= n;
        this.pot += n;
        this.paid[s] = a.to;
        this.target = a.to;
        this.lastRaise = Math.max(this.lastRaise, inc);
        this.acted[s] = true;
        this.acted[op] = false;
        this.turn = op;
      } else throw Error("Invalid betting action");
    } else throw Error("Unknown phase");
    // Do not disclose newly submitted private plans, drafts, bids or gear offers in action history.
    if (["check", "call", "fold", "raise"].includes(a.type))
      this.history.push({
        seat: s,
        round: this.round,
        type: a.type,
        ...(a.type === "raise" ? { amount: a.to } : {}),
      });
  }
}
