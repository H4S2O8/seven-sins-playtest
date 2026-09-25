import { runBattle, type BattleInput } from "../src/battle/engine.js";
import type { BetContext, EatChoice, TeamSetup } from "../src/types.js";

export const bet = (o: Partial<BetContext> = {}): BetContext => ({
  invested: 0, betOrRaiseCount: 0, checkCount: 0, opsPaid: 0, revealedPos: 0, ...o,
});

export function team(
  ids: (string | null)[],
  equip: (string | null)[] = [null, null, null],
  b: Partial<BetContext> = {},
  eat: EatChoice | null = null,
): TeamSetup {
  return { slots: ids.map((c, i) => ({ characterId: c, equipmentId: equip[i] ?? null })), eat, bet: bet(b) };
}

export function battle(a: TeamSetup, b: TeamSetup, o: Partial<BattleInput> = {}) {
  return runBattle({ teams: [a, b], ruleId: "V01", arenaId: "NONE", publicEffectId: null, pot: 0, ...o });
}

/** 第 round 轮结束时，seat 方 pos 号位的血量。 */
export function hpAfter(r: ReturnType<typeof battle>, round: number, seat: 0 | 1, pos: number) {
  return r.timeline[round - 1][seat][pos].hp;
}
