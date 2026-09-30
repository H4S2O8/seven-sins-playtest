import { describe, expect, it } from "vitest";
import { NumericTable } from "../src/numeric/table.js";
import type { NumericAction } from "../src/numeric/types.js";
type Seat = 0 | 1;

function ready(t = new NumericTable({ seed: 71 })) {
  for (const s of [0, 1] as Seat[]) for (let i = 0; i < 3; i++) t.apply(s, { type: "keep", index: 0 });
  for (const s of [0, 1] as Seat[]) t.apply(s, { type: "place", effects: [0, 1, 2], numbers: [0, 1, 2] });
  return t;
}
function act(t: NumericTable, a: NumericAction) { t.apply(t.observe(0).toAct[0] as Seat, a); }
function checks(t: NumericTable) { act(t, { type: "check" }); act(t, { type: "check" }); }
function skip(t: NumericTable) { act(t, { type: "operate", draft: false }); act(t, { type: "operate", draft: false }); }
function vote(t: NumericTable) { act(t, { type: "vote", activate: false }); act(t, { type: "vote", activate: false }); }
function round(t: NumericTable) { checks(t); skip(t); if (t.phase === "vote") vote(t); }
function total(t: NumericTable) { const o = t.observe(0); return o.stacks[0] + o.stacks[1] + o.pot; }

describe("numeric table regressions from browser playtest", () => {
  it("pays the folded pot exactly once and deals a clean second hand", () => {
    const t = ready();
    act(t, { type: "bet", amount: 10 }); act(t, { type: "fold" });
    expect(t.observe(0).stacks).toEqual([98, 102]);
    expect(t.observe(0).result?.payouts).toEqual([0, 14]);
    expect(t.pot).toBe(0);
    t.apply(0, { type: "nextHand" });
    const o = t.observe(0);
    expect(o.handNo).toBe(2); expect(o.dealer).toBe(1); expect(o.phase).toBe("draft");
    expect(o.stacks).toEqual([96, 100]); expect(o.pot).toBe(4); expect(o.result).toBeNull();
    expect(o.me.current).toHaveLength(9); expect(o.me.kept).toEqual([]); expect(o.me.slots).toBeNull();
    expect(total(t)).toBe(200);
  });
  it("ends the fourth idle round instead of requiring eight rounds", () => {
    const t = ready();
    for (let i = 0; i < 3; i++) { round(t); expect(t.phase).toBe("bet"); }
    round(t);
    expect(t.phase).toBe("result"); expect(t.observe(0).round).toBe(4); expect(t.pot).toBe(0);
    expect(total(t)).toBe(200);
  });
  it("keeps paid rounds going, removes equipment after round seven, then settles on checks", () => {
    const t = ready();
    for (let i = 1; i <= 8; i++) {
      act(t, { type: "bet", amount: 2 }); act(t, { type: "call" });
      if (i <= 7) { expect(t.phase).toBe("operate"); skip(t); if (i <= 3) vote(t); }
      expect(t.phase).toBe("bet"); expect(t.observe(0).round).toBe(i + 1);
    }
    checks(t); expect(t.phase).toBe("result"); expect(total(t)).toBe(200);
  });
  it("charges once before showing offers, hides opponent candidates and reveals installs together", () => {
    const t = ready(); checks(t);
    t.apply(0, { type: "operate", draft: true });
    expect(t.observe(0).stacks).toEqual([96, 98]); expect(t.pot).toBe(6);
    expect(t.observe(0).me.offers).toHaveLength(3); expect(t.observe(1).me.offers).toBeNull();
    t.apply(0, { type: "equip", offerIndex: 0, pos: 0 });
    expect(t.observe(1).opponent.equipment).toEqual([null, null, null]);
    t.apply(1, { type: "operate", draft: true });
    expect(t.observe(0).me.offers).toBeNull();
    t.apply(1, { type: "equip", offerIndex: 0, pos: 1 });
    expect(t.observe(1).opponent.equipment[0]).not.toBeNull();
    expect(t.observe(0).opponent.equipment[1]).not.toBeNull();
    expect(t.observe(0).stacks).toEqual([96, 96]); expect(total(t)).toBe(200);
  });
  it("does not refund equipment fees on declining and cannot charge twice", () => {
    const t = ready(); checks(t);
    t.apply(0, { type: "operate", draft: true });
    expect(() => t.apply(0, { type: "operate", draft: true })).toThrow();
    t.apply(0, { type: "operate", draft: false });
    expect(t.observe(0).stacks[0]).toBe(96); expect(t.pot).toBe(6);
    expect(() => t.apply(0, { type: "operate", draft: true })).toThrow();
    t.apply(1, { type: "operate", draft: false }); expect(t.phase).toBe("vote");
  });
  it("rejects ordinary overwrites, but permits weaker replacement in round four", () => {
    const t = ready(); checks(t);
    t.apply(0, { type: "operate", draft: true }); t.apply(0, { type: "equip", offerIndex: 0, pos: 0 });
    t.apply(1, { type: "operate", draft: false }); vote(t); checks(t);
    t.apply(0, { type: "operate", draft: true });
    expect(() => t.apply(0, { type: "equip", offerIndex: 0, pos: 0 })).toThrow();
    t.apply(0, { type: "operate", draft: false }); t.apply(1, { type: "operate", draft: false }); vote(t);
    round(t); checks(t);
    t.apply(0, { type: "operate", draft: true }); t.apply(0, { type: "equip", offerIndex: 0, pos: 0 });
    t.apply(1, { type: "operate", draft: false });
    expect(t.observe(0).me.equipment[0]?.tier).toBe("replace-1"); expect(total(t)).toBe(200);
  });
  it("refunds an unmatched all-in and pays the resulting pot", () => {
    const t = ready(); act(t, { type: "fold" }); t.apply(0, { type: "nextHand" }); ready(t);
    expect(t.observe(0).stacks).toEqual([100, 96]);
    act(t, { type: "allIn" }); act(t, { type: "allIn" });
    const o = t.observe(0);
    expect(o.result?.pot).toBe(196); expect(o.pot).toBe(0); expect(total(t)).toBe(200);
    expect(o.effects.every(e => e.status === "inactive")).toBe(true);
    expect(o.stacks[0]).toBeGreaterThanOrEqual(4);
    expect(o.phase).toBe(o.stacks.includes(0) ? "over" : "result");
  });
  it("splits tied odd pots and awards the spare chip to the dealer", () => {
    const t = ready();
    // Identical cards make the comparison deterministic while fees make the pot odd.
    for (const p of t.players) p.slots = [0, 1, 2].map(() => ({ number: 6, effectId: "GR1", equipment: null }));
    checks(t); skip(t);
    t.apply(0, { type: "vote", activate: false }); t.apply(1, { type: "vote", activate: true });
    t.apply(0, { type: "bid", amount: 1 }); t.apply(1, { type: "bid", amount: 0 });
    round(t); round(t); round(t);
    expect(t.observe(0).result?.winner).toBeNull(); expect(t.observe(0).result?.payouts).toEqual([3, 2]);
    expect(t.observe(0).stacks).toEqual([100, 100]); expect(total(t)).toBe(200);
  });
  it("counts investment across rounds rather than only the last betting round", () => {
    const t = ready();
    t.players[0].slots![0].effectId = "GR1";
    for (let i = 0; i < 3; i++) { act(t, { type: "bet", amount: 5 }); act(t, { type: "call" }); skip(t); vote(t); }
    round(t);
    const trace = t.observe(0).result!.trace!;
    expect(trace.some(x => typeof x !== "string" && x.sourceId === "GR1" && x.seat === 0 && x.after - x.before === 1)).toBe(true);
  });
  it("validates bids and minimum raises without changing chips on invalid input", () => {
    const t = ready();
    expect(() => act(t, { type: "bet", amount: 1 })).toThrow();
    expect(() => act(t, { type: "bet", amount: NaN })).toThrow();
    checks(t); skip(t); t.apply(0, { type: "vote", activate: true }); t.apply(1, { type: "vote", activate: false });
    for (const amount of [-1, 1.5, NaN, Infinity, 21]) expect(() => t.apply(0, { type: "bid", amount })).toThrow();
    t.apply(0, { type: "bid", amount: 0 });
    expect(t.observe(1)).not.toHaveProperty("bids");
    t.apply(1, { type: "bid", amount: 0 }); expect(t.observe(0).effects[0].status).toBe("active");
    expect(total(t)).toBe(200);
  });
  it("handles the last chip spent on equipment and disables unresolved effects", () => {
    const t = ready(new NumericTable({ seed: 1, buyIn: 3 })); checks(t);
    t.apply(0, { type: "operate", draft: true }); expect(t.observe(0).stacks[0]).toBe(0);
    t.apply(0, { type: "equip", offerIndex: 0, pos: 0 }); t.apply(1, { type: "operate", draft: false });
    expect(t.observe(0).result).toBeTruthy(); expect(t.observe(0).effects.every(e => e.status === "inactive")).toBe(true);
    expect(total(t)).toBe(6);
  });
  it("keeps chips conserved through a small multi-hand smoke sample", () => {
    for (let seed = 1; seed <= 5; seed++) {
      const t = new NumericTable({ seed });
      for (let n = 0; n < 2500 && t.phase !== "over" && t.handNo <= 10; n++) {
        if (t.phase === "result") t.apply(0, { type: "nextHand" });
        else { const s = t.observe(0).toAct[0] as Seat; const a = t.baselineAction(s); expect(a).toBeTruthy(); t.apply(s, a!); }
        expect(total(t)).toBe(200); expect(t.observe(0).stacks.every(x => Number.isInteger(x) && x >= 0)).toBe(true);
      }
      expect(t.phase === "over" || t.handNo === 11).toBe(true);
    }
  });
});
