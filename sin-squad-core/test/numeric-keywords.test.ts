import { describe, it, expect } from "vitest";
import {
  runNumericResolution,
  NUMERIC_EQUIPMENT,
  NUMERIC_CHARACTERS,
  NUMERIC_ARENAS,
  NUMERIC_RULES,
  type NumericSlot,
} from "../src/numeric/content.js";
import { Rng } from "../src/rng.js";
const slot = (number = 6, effectId = "WR1", id?: string): NumericSlot => ({
  number,
  effectId,
  equipment: id ? { id, tier: "normal" } : null,
});
const team = () => [slot(), slot(), slot()];
const run = (a: NumericSlot[], b = team(), arenaId = "NA01") =>
  runNumericResolution({ teams: [a, b], arenaId, ruleId: "NR01" });
describe("bounded keyword interactions", () => {
  it("every equipment has standalone value without its bonus condition", () => {
    for (const e of NUMERIC_EQUIPMENT)
      for (const tier of ["normal", "replace-1", "replace-2"] as const) {
        const a = [slot(6), slot(6), slot(6)];
        a[0].equipment = { id: e.id, tier };
        const r = run(a, team(), "NA05");
        expect(r.powers[0][0], e.id + " " + tier).toBeGreaterThan(6);
      }
  });
  it("battery accepts own, allied and equipment gains, and works without interception", () => {
    for (const a of [
      [slot(8, "PR1", "E18"), slot(), slot()],
      [slot(6, "WR1", "E18"), slot(6, "LU5"), slot()],
      [slot(6, "WR1", "E18"), slot(6, "WR1", "E05"), slot()],
    ]) {
      const r = run(a);
      const plain = structuredClone(a);
      plain[0].equipment = { id: "E01", tier: "replace-2" };
      expect(
        r.trace.some(
          (t) => t.sourceId === "E18" && t.text.includes("充能奖励"),
        ),
      ).toBe(true);
      expect(r.powers[0][0]).toBeGreaterThan(run(plain).powers[0][0]);
    }
  });
  it("battery protects only stored gain, interception still takes overflow", () => {
    const a = [slot(8, "PR1", "E18"), slot(), slot()],
      b = [slot(6, "EN1"), slot(), slot()];
    const r = run(a, b);
    expect(
      r.trace.some((t) => t.sourceId === "EN1" && t.text.includes("截流夺取")),
    ).toBe(false);
    a[1] = slot(9, "PR3");
    const overflow = run(a, b);
    expect(
      overflow.trace.some(
        (t) => t.sourceId === "EN1" && t.text.includes("截流夺取"),
      ),
    ).toBe(true);
  });
  it("shield blocks hostile control once, guard can protect a neighbor", () => {
    const a = [slot(6, "WR1", "E09"), slot(6, "WR1", "E10"), slot()],
      b = [slot(6, "LU2"), slot(), slot(6, "LU2")];
    const r = run(a, b);
    expect(r.silenced[0]).toEqual([false, true, false]);
    expect(r.trace.some((t) => t.text.includes("护送"))).toBe(true);
  });
  it("silenced legacy remains useful and reaches another ally", () => {
    const a = [slot(8, "GL3"), slot(3), slot(6)];
    const r = run(a, team(), "NA05");
    expect(r.powers[0]).toEqual([8, 7, 6]);
    expect(
      r.trace.some((t) => t.sourceId === "GL3" && t.stage === "keyword"),
    ).toBe(true);
  });
  it("a feeding ally triggers resonance once without recursive cycles", () => {
    const a = [
      slot(5, "LU4", "E14"),
      slot(6, "LU5", "E14"),
      slot(4, "LU4", "E14"),
    ];
    const r = run(a);
    expect(
      r.trace.filter((t) => t.text.includes("共鸣：")).length,
    ).toBeLessThanOrEqual(3);
    expect(r.trace.some((t) => t.text.includes("共鸣："))).toBe(true);
  });
  it("rage compensates actual enemy reductions but not a shielded one", () => {
    const a = [slot(7, "WR2", "E21"), slot(), slot()],
      b = [slot(3, "GL1"), slot(), slot()];
    const r = run(a, b);
    expect(r.trace.filter((t) => t.text.includes("激怒："))).toHaveLength(1);
    a[0].equipment = { id: "E09", tier: "normal" };
    expect(run(a, b).trace.some((t) => t.text.includes("激怒："))).toBe(false);
  });
  it("pursuit uses one shared snapshot and stops after one wave", () => {
    const a = [slot(10, "GL5", "E24"), slot(3), slot(4)];
    const r = run(a);
    expect(r.trace.filter((t) => t.text.includes("追猎："))).toHaveLength(1);
    expect(r.powers[1][1]).toBeLessThan(6);
  });
  it("swapping seats swaps the outcome and fast evaluation matches replay across mixed loadouts", () => {
    const rng = new Rng(913);
    for (let i = 0; i < 160; i++) {
      const teams = Array.from({ length: 2 }, () =>
        Array.from({ length: 3 }, () =>
          slot(
            3 + rng.int(8),
            rng.pick(NUMERIC_CHARACTERS).id,
            rng.pick(NUMERIC_EQUIPMENT).id,
          ),
        ),
      ) as [NumericSlot[], NumericSlot[]];
      const input = {
        teams,
        arenaId: rng.pick(NUMERIC_ARENAS).id,
        ruleId: rng.pick(NUMERIC_RULES).id,
      };
      const r = runNumericResolution(input),
        flip = runNumericResolution({ ...input, teams: [teams[1], teams[0]] });
      expect(flip.powers).toEqual([r.powers[1], r.powers[0]]);
      expect(flip.winner).toBe(r.winner === null ? null : 1 - r.winner);
      expect(runNumericResolution({ ...input, recordTrace: false })).toEqual({
        ...r,
        trace: [],
      });
      expect(
        r.powers.flat().every((n) => Number.isInteger(n) && n >= 0 && n < 100),
      ).toBe(true);
    }
  });
  it("at least half the characters and equipment have real keywords", () => {
    expect(
      NUMERIC_CHARACTERS.filter((c) => c.keywords?.length).length,
    ).toBeGreaterThanOrEqual(15);
    expect(
      NUMERIC_EQUIPMENT.filter((c) => c.keywords?.length).length,
    ).toBeGreaterThanOrEqual(12);
    expect(NUMERIC_CHARACTERS.some((c) => (c.keywords?.length ?? 0) > 1)).toBe(
      true,
    );
  });
  it("inspiration counts distinct live keywords; command needs a protected ally; alliance spans cards", () => {
    const a = [slot(6, "GR1"), slot(6, "LU1"), slot(6, "WR1")];
    const r = run(a);
    expect(
      r.trace.find((t) => t.sourceId === "GR1" && t.text.startsWith("激励："))
        ?.after,
    ).toBe(9);
    const king = run([slot(6, "PR3"), slot(6, "SL3"), slot()]);
    expect(king.trace.some((t) => t.text.startsWith("统御："))).toBe(true);
    const isolated = run([slot(6, "PR3"), slot(), slot()]);
    expect(isolated.trace.some((t) => t.text.startsWith("统御："))).toBe(false);
    const pact = run([slot(), slot(6, "GR3", "E18"), slot()]);
    expect(pact.trace.filter((t) => t.text.startsWith("结盟："))).toHaveLength(
      2,
    );
  });
});

it("support still resonates when fully stored, and derived resonance can fill another battery", () => {
  const r = run([slot(5, "WR1", "E22"), slot(8, "LU5"), slot(3, "WR1", "E18")]);
  expect(
    r.trace.some((t) => t.sourceId === "E22" && t.text.startsWith("共鸣：")),
  ).toBe(true);
  expect(
    r.trace.filter((t) => t.sourceId === "E18" && t.text.startsWith("蓄能暂存"))
      .length,
  ).toBeGreaterThanOrEqual(2);
  expect(
    r.trace.some((t) => t.sourceId === "E18" && t.text.includes("充能奖励 2")),
  ).toBe(true);
});
it("devour triggers legacy which feeds the recipient battery", () => {
  const r = run([slot(8, "GL3"), slot(3, "GL2", "E18"), slot(6)]);
  expect(r.silenced[0][0]).toBe(true);
  expect(r.trace.some((t) => t.text.startsWith("遗赠"))).toBe(true);
  expect(
    r.trace.some((t) => t.sourceId === "E18" && t.text.includes("充能奖励 2")),
  ).toBe(true);
});
it("alliance support can resonate and charge a battery in a bounded chain", () => {
  const r = run([slot(5, "LU4"), slot(8, "GR3", "E18"), slot(3, "WR1", "E18")]);
  expect(r.trace.some((t) => t.text.startsWith("结盟"))).toBe(true);
  expect(r.trace.some((t) => t.text.startsWith("共鸣"))).toBe(true);
  expect(
    r.trace.some((t) => t.targetPos === 2 && t.text.includes("充能奖励 2")),
  ).toBe(true);
});
it("protected allies enable command which can power pursuit on the same unit", () => {
  const r = run([slot(5, "LU1"), slot(8, "PR3", "E24"), slot(3)]);
  expect(
    r.trace.some((t) => t.sourceId === "PR3" && t.text.startsWith("统御")),
  ).toBe(true);
  expect(
    r.trace.some((t) => t.sourceId === "E24" && t.text.startsWith("追猎")),
  ).toBe(true);
});

it("rage accepts friendly sacrifice and intercepted gains, not just a rare hostile debuff", () => {
  const sacrifice = run([slot(6, "LU1", "E21"), slot(), slot()]);
  expect(
    sacrifice.trace.some(
      (t) => t.sourceId === "E21" && t.text.startsWith("激怒"),
    ),
  ).toBe(true);
  const intercepted = run(
    [slot(8, "WR2"), slot(), slot()],
    [slot(10, "EN1"), slot(), slot()],
  );
  expect(intercepted.trace.some((t) => t.text.startsWith("截流"))).toBe(true);
  expect(
    intercepted.trace.some(
      (t) => t.sourceId === "WR2" && t.text.startsWith("激怒"),
    ),
  ).toBe(true);
});
