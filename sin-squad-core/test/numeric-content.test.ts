import { describe, expect, it } from "vitest";
import { CHARACTERS } from "../src/content/characters.js";
import {
  NUMERIC_ARENAS,
  NUMERIC_CHARACTERS,
  NUMERIC_EFFECTS,
  NUMERIC_EQUIPMENT,
  NUMERIC_RULES,
  characterById,
  equipmentById,
  runNumericResolution,
  type NumericSlot,
} from "../src/numeric/content.js";

const slot = (number: number, effectId: string, equipment: string | null = null): NumericSlot => ({
  number,
  effectId,
  equipment: equipment ? { id: equipment, tier: "normal" } : null,
});

describe("numeric mode content", () => {
  it("keeps every original character name and exposes one executable rule", () => {
    expect(NUMERIC_CHARACTERS).toHaveLength(29);
    for (const c of NUMERIC_CHARACTERS) {
      expect(c.name).toBe(CHARACTERS.find(original => original.id === c.id)?.name);
      expect(c.name.length).toBeGreaterThan(0);
      expect(c.text.length).toBeGreaterThan(0);
      expect(characterById(c.id).rules.length).toBeGreaterThan(0);
    }
  });

  it("has the agreed environment pool sizes", () => {
    expect(NUMERIC_ARENAS).toHaveLength(8);
    expect(NUMERIC_RULES).toHaveLength(8);
    expect(NUMERIC_EFFECTS).toHaveLength(12);
    expect(NUMERIC_EQUIPMENT).toHaveLength(24);
  });

  it("keeps normal and replacement equipment versions separate", () => {
    expect(equipmentById("E01", "normal").text).toContain("+3");
    expect(equipmentById("E01", "replace-1").text).toContain("+2");
    expect(equipmentById("E01", "replace-2").text).toContain("+1");
    expect(equipmentById("E01", "normal").tier).toBe("normal");
  });

  it("resolves fixed 1-v-1, 2-v-2, 3-v-3 and never produces negative power", () => {
    const result = runNumericResolution({
      teams: [
        [slot(3, "WR1", "E01"), slot(7, "SL3"), slot(10, "PR1")],
        [slot(9, "WR1"), slot(4, "SL1"), slot(8, "PR1")],
      ],
      arenaId: "NA01",
      ruleId: "NR01",
      activeEffectIds: ["NF05"],
      stats: [{ invested: 20, betOrRaise: 2, checks: 1, opsPaid: 1, stack: 10, round: 4 }, { invested: 30, betOrRaise: 1, stack: 5, round: 4 }],
    });
    expect(result.powers).toHaveLength(2);
    expect(result.powers.flat()).toHaveLength(6);
    expect(result.powers.flat().every((n) => Number.isInteger(n) && n >= 0)).toBe(true);
    expect(result.lineWinners).toHaveLength(3);
    expect(result.lines[0]).toMatch(/1号位/);
  });

  it("lets silent field effects remove character bonuses while equipment still resolves", () => {
    const base = runNumericResolution({
      teams: [[slot(8, "PR1", "E01"), slot(6, "WR1"), slot(6, "WR1")], [slot(8, "WR1"), slot(6, "WR1"), slot(6, "WR1")]],
      arenaId: "NA01", ruleId: "NR01", activeEffectIds: [],
    });
    const silent = runNumericResolution({
      teams: [[slot(8, "PR1", "E01"), slot(6, "WR1"), slot(6, "WR1")], [slot(8, "WR1"), slot(6, "WR1"), slot(6, "WR1")]],
      arenaId: "NA05", ruleId: "NR01", activeEffectIds: [],
    });
    expect(silent.silenced[0][0]).toBe(true);
    expect(silent.trace.some((t) => t.sourceId === "E01")).toBe(true);
    expect(silent.powers[0][0]).toBe(11);
    expect(base.powers[0][0]).toBe(13);
  });

  it("supports position conditions and a low-beats-high field bonus", () => {
    const result = runNumericResolution({
      teams: [[slot(3, "WR1"), slot(6, "WR1"), slot(10, "WR1")], [slot(9, "WR1"), slot(6, "WR1"), slot(3, "WR1")]],
      arenaId: "NA07", ruleId: "NR04", activeEffectIds: [],
    });
    expect(result.powers[0][0]).toBeGreaterThan(3);
    expect(result.powers[1][2]).toBeGreaterThan(3);
    expect(result.lineWinners).toHaveLength(3);
  });

  it("activates every character with an explicit satisfying fixture", () => {
    const fixtures: Record<string, { nums?: number[]; foe?: number[]; pos?: number; equipment?: boolean; opponentEquipment?: boolean; ops?: number }> = {
      WR1: {}, WR2: { nums: [3, 6, 8], foe: [8, 6, 7] }, WR3: {}, GR1: {}, GR2: {}, GR3: { equipment: true },
      GL1: { nums: [3, 6, 8], foe: [8, 6, 7] }, GL2: { nums: [8, 4, 6], pos: 1 }, GL3: { nums: [3, 6, 8], foe: [6, 6, 7] },
      EN1: { nums: [6, 4, 8], foe: [6, 6, 7] }, EN2: { nums: [3, 6, 8], foe: [8, 6, 7] }, EN3: { opponentEquipment: true },
      SL1: {}, SL2: { nums: [3, 6, 8] }, SL3: { ops: 0 }, PR1: { nums: [8, 6, 3] }, PR2: { nums: [9, 6, 3], foe: [3, 6, 7] },
      PR3: { nums: [9, 6, 3] }, LU1: {}, LU2: {}, LU3: { nums: [3, 6, 8], foe: [8, 6, 7] }, WR4: { opponentEquipment: true }, GR4: {},
      GL4: { opponentEquipment: true }, GL5: { foe: [3, 8, 9] }, EN4: { foe: [8, 6, 7] }, SL4: {}, LU4: { nums: [3, 6, 8], foe: [8, 6, 7] }, LU5: { pos: 1 },
    };
    for (const c of NUMERIC_CHARACTERS) {
      const f = fixtures[c.id], pos = f.pos ?? 0;
      const own = (f.nums ?? [6, 4, 8]).map(n => slot(n, "WR1", f.equipment ? "E01" : null));
      own[pos].effectId = c.id;
      const foe = (f.foe ?? [6, 6, 7]).map(n => slot(n, "WR1", f.opponentEquipment ? "E01" : null));
      const result = runNumericResolution({ teams: [own, foe], arenaId: "NA01", ruleId: "NR01", stats: [{ invested: 50, opsPaid: f.ops ?? 3, checks: 3, stack: 100, round: 5 }, { betOrRaise: 3, stack: 20 }] });
      expect(result.trace.some(t => t.sourceId === c.id && t.seat === 0), c.id).toBe(true);
    }
  });

  it("applies silence and equipment sealing as actual control, including mutual silence", () => {
    const result = runNumericResolution({
      teams: [
        [slot(6, "LU2"), slot(6, "EN3"), slot(6, "WR1")],
        [slot(6, "LU2"), slot(6, "PR1", "E01"), slot(6, "WR1")],
      ], arenaId: "NA01", ruleId: "NR01",
    });
    expect(result.silenced[0][0]).toBe(true);
    expect(result.silenced[1][0]).toBe(true);
    expect(result.sealed[1][1]).toBe(true);
    expect(result.powers[1][1]).toBe(6);
    expect(result.powers[0][1]).toBe(7);
  });

  it("turns a majority loss into a total-power victory under a different rule", () => {
    const teams: [NumericSlot[], NumericSlot[]] = [[slot(10, "WR1", "E01"), slot(5, "WR1"), slot(5, "WR1")], [slot(3, "WR1"), slot(6, "WR1"), slot(6, "WR1")]];
    expect(runNumericResolution({ teams, arenaId: "NA05", ruleId: "NR01" }).winner).toBe(1);
    expect(runNumericResolution({ teams, arenaId: "NA05", ruleId: "NR05" }).winner).toBe(0);
  });

  it("activates all 24 equipment mechanisms and weakens only newly chosen versions", () => {
    const fixtures: Record<string, { nums?: number[]; foe?: number[]; pos?: number; silent?: boolean }> = {
      E01: {}, E02: { nums: [3, 6, 8] }, E03: {}, E04: { foe: [3, 6, 8] }, E05: { pos: 1 }, E06: { foe: [3, 6, 8] }, E07: { foe: [8, 6, 8] },
      E08: { nums: [8, 6, 3] }, E09: {}, E10: { nums: [3, 8, 9] }, E11: { nums: [3, 8, 9] }, E12: {}, E13: { nums: [3, 6, 8], foe: [8, 6, 8] },
      E14: {}, E15: { nums: [3, 8, 5], pos: 1 }, E16: { nums: [8, 3, 9], pos: 1 }, E17: { nums: [3, 9, 4], pos: 1 }, E18: { nums: [3, 4, 5], foe: [8, 9, 10] },
      E19: { nums: [7, 8, 9] }, E20: { silent: true }, E21: { silent: true }, E22: { nums: [3, 8, 9], foe: [8, 6, 8] }, E23: { nums: [3, 5, 7], pos: 1 }, E24: { nums: [8, 5, 7], foe: [8, 3, 8], pos: 1 },
    };
    for (const eq of NUMERIC_EQUIPMENT) {
      const f = fixtures[eq.id], pos = f.pos ?? 0;
      const totals: number[] = [];
      for (const tier of ["normal", "replace-1", "replace-2"] as const) {
        const own = (f.nums ?? [6, 4, 8]).map(n => slot(n, "WR1")); own[pos].equipment = { id: eq.id, tier };
        const foe = (f.foe ?? [6, 4, 8]).map(n => slot(n, "WR1"));
        const r = runNumericResolution({ teams: [own, foe], arenaId: f.silent ? "NA05" : "NA01", ruleId: "NR01" });
        const eqTrace = r.trace.filter(t => t.sourceId === eq.id && t.seat === 0);
        expect(eqTrace.length, eq.id).toBeGreaterThan(0);
        totals.push(eqTrace.reduce((n, t) => n + (t.after-t.before)*(t.targetSeat===0?1:-1), 0));
      }
      expect(totals[0], eq.id).toBeGreaterThanOrEqual(totals[1]);
      expect(totals[1], eq.id).toBeGreaterThanOrEqual(totals[2]);
      const ks=['normal','replace-1','replace-2'].map(t=>equipmentById(eq.id,t as 'normal').keywords?.[0]?.value??0);
      expect(ks[0]).toBeGreaterThanOrEqual(ks[1]);expect(ks[1]).toBeGreaterThanOrEqual(ks[2]);
    }
  });
});
