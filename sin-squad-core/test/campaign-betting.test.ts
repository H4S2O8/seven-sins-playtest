import { describe, expect, it } from "vitest";
import { newProgress, stageTable } from "../src/campaign/progress.js";
import { MAX_RAISES, Table } from "../src/game/table.js";
import { legalActions, observe } from "../src/game/view.js";
import type { Phase } from "../src/game/actions.js";

/** 第 1 关的牌桌（固定额下注 + 第二次翻开）。 */
function stageOne(seed = 3) {
  const p = newProgress();
  p.cleared = 1;
  return new Table(stageTable(p, 1, seed));
}

/** 双方都走第一个合法动作，直到进入 phase。 */
function advanceTo(t: Table, phase: Phase) {
  for (let i = 0; i < 50 && t.phase !== phase; i++) {
    for (const s of t.toAct()) if (t.toAct().includes(s)) t.apply(s, legalActions(t, s)[0]);
  }
  expect(t.phase).toBe(phase);
}

describe("固定额下注", () => {
  it("第 1 轮每次 10：下注只能 10，加注只能加 10", () => {
    const t = stageOne();
    advanceTo(t, "bet");
    const a = t.hand.actor;
    expect(() => t.apply(a, { type: "bet", amount: 15 })).toThrow();
    expect(legalActions(t, a)).toContainEqual({ type: "bet", amount: 10 });
    t.apply(a, { type: "bet", amount: 10 });
    const b = t.hand.actor;
    expect(() => t.apply(b, { type: "raise", to: 30 })).toThrow();
    t.apply(b, { type: "raise", to: 20 });
    expect(t.hand.roundBet[b]).toBe(20);
  });

  it(`每轮最多加注 ${MAX_RAISES} 次，之后只能跟注或弃牌`, () => {
    const t = stageOne();
    advanceTo(t, "bet");
    t.apply(t.hand.actor, { type: "bet", amount: 10 });
    for (let i = 1; i <= MAX_RAISES; i++) t.apply(t.hand.actor, { type: "raise", to: 10 + 10 * i });
    const s = t.hand.actor;
    expect(() => t.apply(s, { type: "raise", to: 50 })).toThrow();
    expect(() => t.apply(s, { type: "allIn" })).toThrow();
    expect(legalActions(t, s).map((x) => x.type).sort()).toEqual(["call", "fold"]);
    expect(observe(t, s).betting.raisesLeft).toBe(0);
  });

  it("筹码够下注时不能全押", () => {
    const t = stageOne();
    advanceTo(t, "bet");
    expect(() => t.apply(t.hand.actor, { type: "allIn" })).toThrow();
    expect(legalActions(t, t.hand.actor).some((x) => x.type === "allIn")).toBe(false);
  });
});

describe("第二次翻开", () => {
  it("第 1 轮下注之后双方暗选再翻开一名，一起翻开，然后第 2 轮每次 20", () => {
    const t = stageOne();
    advanceTo(t, "bet");
    t.apply(t.hand.actor, { type: "check" });
    t.apply(t.hand.actor, { type: "check" });
    expect(t.phase).toBe("reveal2");
    expect(t.toAct()).toEqual([0, 1]);
    const hidden0 = t.hiddenPositions(0);
    const hidden1 = t.hiddenPositions(1);
    t.apply(0, { type: "reveal2", pos: hidden0[0] });
    // 对手还没选之前看不到我翻了谁
    expect(observe(t, 1).opponent.revealed2).toBeNull();
    expect(() => t.apply(0, { type: "reveal2", pos: hidden0[1] })).toThrow();
    t.apply(1, { type: "reveal2", pos: hidden1[1] });
    expect(observe(t, 1).opponent.revealed2).toEqual({ pos: hidden0[0], characterId: t.hand.placement[0]!.slots[hidden0[0]] });
    expect(t.log.at(-1)?.type).toBe("reveal2");
    expect(t.phase).toBe("bet");
    expect(t.hand.betRound).toBe(2);
    expect(legalActions(t, t.hand.actor)).toContainEqual({ type: "bet", amount: 20 });
  });

  it("不能翻已经亮出的那名", () => {
    const t = stageOne();
    advanceTo(t, "bet");
    t.apply(t.hand.actor, { type: "check" });
    t.apply(t.hand.actor, { type: "check" });
    expect(() => t.apply(0, { type: "reveal2", pos: t.hand.placement[0]!.reveal })).toThrow();
  });

  it("自由牌桌没有这两条", () => {
    const t = new Table({ seed: 3 });
    advanceTo(t, "bet");
    expect(observe(t, t.hand.actor).betting.step).toBeNull();
    expect(legalActions(t, t.hand.actor).some((x) => x.type === "bet" && x.amount !== 10)).toBe(true);
  });
});
