import { describe, expect, it } from "vitest";
import { runTraditionalBattle, traditionalPower } from "../src/battle/traditional.js";

describe("传统单数值战斗", () => {
  it("数字与效果按对位比较", () => {
    const r = runTraditionalBattle({ teams: [
      [{ effectId: "WR3", number: 8 }, { effectId: "SL4", number: 3 }, { effectId: "LU2", number: 6 }],
      [{ effectId: "WR1", number: 7 }, { effectId: "GR1", number: 2 }, { effectId: "LU2", number: 6 }],
    ] });
    expect(r.winner).toBe(0);
    expect(r.events).toHaveLength(3);
  });
  it("改指向只改变比较对象，不改变数字或装备", () => {
    const base = { effectId: "EN2", number: 4, equipmentId: "E01" };
    expect(traditionalPower(base, { effectId: "WR1", number: 9 }, 0, [base], [{ effectId: "WR1", number: 9 }]))
      .toBeGreaterThan(4);
  });
});
