import { IntentTable } from "./table.js";
import { INTENT_RULESET } from "./content.js";
import type { Action, Seat } from "./types.js";

export interface IntentSave {
  version: typeof INTENT_RULESET;
  seed: number;
  hand: number;
  stacks: [number, number];
  log: { seat: Seat; action: Action }[];
}
/** Replay preserves private pending choices, RNG and paid-but-not-yet-equipped offers. */
export class IntentSession {
  table: IntentTable;
  log: IntentSave["log"] = [];
  constructor(
    readonly seed: number,
    readonly hand = 1,
    readonly stacks: [number, number] = [100, 100],
  ) {
    this.table = new IntentTable(seed, (hand % 2) as Seat, stacks);
  }
  act(seat: Seat, action: Action) {
    this.table.act(seat, action);
    this.log.push({ seat, action: structuredClone(action) });
  }
  save(): IntentSave {
    return {
      version: INTENT_RULESET,
      seed: this.seed,
      hand: this.hand,
      stacks: this.stacks,
      log: structuredClone(this.log),
    };
  }
  static restore(data: IntentSave) {
    if (
      !data ||
      data.version !== INTENT_RULESET ||
      !Number.isInteger(data.seed) ||
      !Number.isInteger(data.hand) ||
      data.hand < 1 ||
      !Array.isArray(data.log) ||
      data.log.length > 10000 ||
      !Array.isArray(data.stacks) ||
      data.stacks.length !== 2
    )
      throw Error("Incompatible save");
    const s = new IntentSession(data.seed, data.hand, data.stacks);
    for (const e of data.log) s.act(e.seat, e.action);
    return s;
  }
  next(seed: number) {
    if (!this.table.result || this.table.stacks.some((n) => n <= 0))
      throw Error("Cannot start next hand");
    return new IntentSession(seed, this.hand + 1, [...this.table.stacks]);
  }
}
