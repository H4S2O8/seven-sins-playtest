import { describe, expect, it } from "vitest";
import { NumericTable } from "../src/numeric/table.js";

function finish(t: NumericTable) {
  let guard = 0;
  while (t.phase !== "result" && t.phase !== "over" && guard++ < 200) {
    const o = t.observe(0);
    for (const s of o.toAct) {
      const a = t.aiAction?.(s as 1);
      if (a) t.apply(s as 1, a);
    }
    if (!o.toAct.length) break;
  }
  return guard;
}

describe("numeric table harness", () => {
  it("runs deterministic AI table to a real result", () => {
    const t = new NumericTable({ seed: 7 });
    const n = finish(t);
    expect(n).toBeLessThan(200);
    expect(["result", "over"]).toContain(t.phase);
    expect(t.observe(0).result).toBeTruthy();
  });
  it("keeps opponent hidden until resolution", () => {
    const t = new NumericTable({ seed: 8 });
    const o = t.observe(0);
    expect(o.opponent.tiers).toHaveLength(3);
    expect(o.opponent.placed).toBe(false);
    expect(o.me.numbers).toHaveLength(3);
  });
});
