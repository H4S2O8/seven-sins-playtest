import { describe, expect, it } from "vitest";
import { Rng } from "../src/rng.js";
import { battle } from "../src/intent/battle.js";
import { Bot } from "../src/intent/agent.js";
import {
  CARDS,
  FIELDS,
  GEARS,
  plans,
  signal,
  sinOf,
} from "../src/intent/content.js";
import { IntentTable } from "../src/intent/table.js";
import { ProcessFields } from "../src/intent/fields.js";
import { OFF, type Unit } from "../src/intent/types.js";
const u = (
  id = "EN3",
  raw = 6,
  gear: string | null = null,
  plan = OFF(),
): Unit => ({ id, raw, gear, plan });
const neutral = () => [u(), u(), u()];
function placed(seed = 7) {
  const t = new IntentTable(seed);
  for (const s of [0, 1] as const)
    t.act(s, { type: "draft", indices: [0, 1, 2] });
  for (const s of [0, 1] as const)
    t.act(s, { type: "place", units: [0, 1, 2], numbers: [0, 1, 2] });
  return t;
}
function passiveRound(t: IntentTable) {
  while (!t.result && t.phase !== "operate") {
    const s = t.actors()[0];
    if (t.phase.includes("plan"))
      t.act(s, { type: "plan", plans: [OFF(), OFF(), OFF()] });
    else if (t.phase === "bet") t.act(s, { type: "check" });
    else if (t.phase === "bid")
      t.act(s, { type: "bid", yes: false, amount: 0 });
    else throw Error(t.phase);
  }
}
describe("intent design harness: executable invariants", () => {
  it("equipment has no unconditional base power", () => {
    for (const g of GEARS)
      expect(
        battle([[u("EN3", 6, g.id), u(), u()], neutral()]).powers[0],
      ).toEqual([6, 6, 6]);
  });
  it("a redirected support packet can enter another equipment capacitor", () => {
    const own = [
      u("WR2", 6, null, {
        on: true,
        targets: [{ side: "ally", pos: 1 }],
        mode: 0,
      }),
      u("SL3", 6, null, {
        on: true,
        targets: [{ side: "ally", pos: 2 }],
        mode: 0,
      }),
      u("EN3", 6, "G09"),
    ];
    const b = battle([own, neutral()]);
    expect(b.powers[0]).toEqual([4, 5, 12]);
  });
  it("exchanges a support destination once rather than bouncing forever", () => {
    const own = [
      u("WR2", 6, null, {
        on: true,
        targets: [{ side: "ally", pos: 1 }],
        mode: 0,
      }),
      u("PR2", 6, null, {
        on: true,
        targets: [{ side: "ally", pos: 2 }],
        mode: 0,
      }),
      u(),
    ];
    expect(battle([own, neutral()]).powers[0]).toEqual([4, 5, 10]);
  });
  it("has no arena in the table observation and starts at raw power", () => {
    const t = new IntentTable(1);
    expect(t.observe(0)).not.toHaveProperty("arena");
    expect(
      battle([[u("EN3", 3), u("EN3", 10), u("EN3", 7)], neutral()]).powers[0],
    ).toEqual([3, 10, 7]);
  });
  it("five transferred pays five and receives ten, not ten paid", () => {
    const fields = new ProcessFields(["F1"]);
    expect(fields.transfer(5)).toBe(10);
    const own = [
      u("GL2", 10, null, {
        on: true,
        targets: [{ side: "ally", pos: 1 }],
        mode: 0,
      }),
      u("EN3", 4),
      u(),
    ];
    expect(battle([own, neutral()], ["F1"]).powers[0]).toEqual([7, 10, 6]);
  });
  it("drain doubles only the real post-block receipt", () => {
    const own = [
      u("GL1", 6, null, {
        on: true,
        targets: [{ side: "enemy", pos: 0 }],
        mode: 0,
      }),
      u(),
      u(),
    ];
    const b = battle([own, [u("EN3", 6, "G04"), u(), u()]], ["F1"]);
    expect(b.powers[0][0]).toBe(8);
    expect(b.powers[1][0]).toBe(5);
  });
  it("transfer amplification does not double the independent bonus", () => {
    const own = [
      u("WR2", 6, null, {
        on: true,
        targets: [{ side: "ally", pos: 1 }],
        mode: 0,
      }),
      u(),
      u(),
    ];
    expect(battle([own, neutral()], ["F1"]).powers[0]).toEqual([4, 12, 6]);
  });
  it("redirected gains amplify the receipt without charging the original receiver twice", () => {
    const own = [
      u("EN2", 6, "G02", { on: true, targets: [], mode: 1 }),
      u(),
      u(),
    ];
    expect(battle([own, neutral()], ["F1"]).powers[0]).toEqual([7, 8, 6]);
  });
  it("overflow is delayed, not lost or repeatedly amplified on release", () => {
    const own = [
      u("WR2", 6, null, {
        on: true,
        targets: [{ side: "ally", pos: 1 }],
        mode: 0,
      }),
      u(),
      u(),
    ];
    const b = battle([own, neutral()], ["F1", "F5"]);
    expect(b.powers[0]).toEqual([4, 12, 6]);
    expect(b.trace.some((e) => e.modifiers.includes("F5:5"))).toBe(true);
  });
  it("support relays once to the right and field output does not recurse", () => {
    const own = [
      u("WR2", 6, null, {
        on: true,
        targets: [{ side: "ally", pos: 1 }],
        mode: 0,
      }),
      u(),
      u(),
    ];
    expect(battle([own, neutral()], ["F2"]).powers[0]).toEqual([4, 10, 10]);
  });
  it("a real blocked hit supports the left neighbour", () => {
    const attack = u("WR1", 6, null, {
      on: true,
      targets: [{ side: "enemy", pos: 0 }],
      mode: 0,
    });
    expect(
      battle(
        [
          [attack, u(), u()],
          [u("EN3", 6, "G05"), u(), u()],
        ],
        ["F3"],
      ).powers[1],
    ).toEqual([6, 6, 9]);
  });
  it("real cost fuels the next skill gain", () => {
    const own = [
      u("WR2", 6, null, {
        on: true,
        targets: [{ side: "ally", pos: 1 }],
        mode: 0,
      }),
      u(),
      u(),
    ];
    expect(battle([own, neutral()], ["F4"]).powers[0]).toEqual([4, 12, 6]);
  });
  it("an arrived support protects against a later attack but not its own cost", () => {
    const own = [
      u("WR2", 6, null, {
        on: true,
        targets: [{ side: "ally", pos: 1 }],
        mode: 0,
      }),
      u(),
      u(),
    ];
    const foe = [
      u("WR1", 6, null, {
        on: true,
        targets: [{ side: "enemy", pos: 1 }],
        mode: 0,
      }),
      u(),
      u(),
    ];
    expect(battle([own, foe], ["F6"]).powers[0]).toEqual([4, 10, 6]);
  });
  it("the weakest unit can collect another characters self reinforcement", () => {
    const own = [
      u("EN2", 8, null, { on: true, targets: [], mode: 1 }),
      u("EN3", 3),
      u("EN3", 6),
    ];
    expect(battle([own, neutral()], ["F7"]).powers[0]).toEqual([7, 6, 6]);
  });
  it("blessings become attacks without also granting the original gain", () => {
    const own = [
      u("WR2", 6, null, {
        on: true,
        targets: [{ side: "ally", pos: 1 }],
        mode: 0,
      }),
      u(),
      u(),
    ];
    const b = battle([own, neutral()], ["F8"]);
    expect(b.powers).toEqual([
      [4, 6, 6],
      [6, 2, 6],
    ]);
  });
  it("several routing receivers can amplify, but a gate cannot recurse into itself", () => {
    const own = [
      u("EN2", 6, "G02", { on: true, targets: [], mode: 1 }),
      u("EN3", 4, "G13"),
      u("EN3", 5, "G03"),
    ];
    const b = battle([own, neutral()], ["F1", "F2", "F7"]);
    expect(b.powers.flat().every((n) => Number.isFinite(n) && n >= 0)).toBe(
      true,
    );
    expect(b.trace.length).toBeLessThan(100);
  });
  it("reveals one active opening effect and no future identities before drafting", () => {
    const t = new IntentTable(16),
      o = t.observe(0);
    expect(t.effects).toHaveLength(4);
    expect(new Set(t.effects.map((e) => e.id)).size).toBe(4);
    expect(o.effects[0]).toEqual({ ...t.effects[0], active: true });
    expect(o.effects.slice(1)).toEqual(
      Array.from({ length: 3 }, () => ({ id: null, active: null })),
    );
  });
  it("reveals exactly one more effect after each equipment window, then auctions it", () => {
    const t = placed(17);
    passiveRound(t);
    for (let round = 1; round <= 3; round++) {
      expect(t.round).toBe(round);
      for (const s of [0, 1] as const)
        t.act(s, { type: "operate", buy: false });
      expect(t.phase).toBe("bid");
      expect(t.observe(0).effects.filter((e) => e.id !== null)).toHaveLength(
        round + 1,
      );
      t.act(0, { type: "bid", yes: true, amount: 1 });
      expect(t.observe(1).effects[round].active).toBeNull();
      t.act(1, { type: "bid", yes: false, amount: 0 });
      expect(t.effects[round].active).toBe(true);
      expect(t.effects.filter((e) => e.active)).toEqual([t.effects[round]]);
      for (const s of [0, 1] as const)
        t.act(s, { type: "plan", plans: [OFF(), OFF(), OFF()] });
      if (round < 3) passiveRound(t);
    }
    expect(t.round).toBe(4);
    expect(t.effects).toHaveLength(4);
    expect(t.observe(0).effects.every((e) => e.id !== null)).toBe(true);
    expect(() =>
      t.act(t.actors()[0], { type: "operate", buy: true }),
    ).toThrow();
    expect(() =>
      t.act(t.actors()[0], { type: "bid", yes: true, amount: 1 }),
    ).toThrow();
  });
  it("each pair of process fields remains finite with mixed characters and equipment", () => {
    const rng = new Rng(297);
    for (let a = 0; a < FIELDS.length; a++)
      for (let b = a + 1; b < FIELDS.length; b++)
        for (let k = 0; k < 4; k++) {
          const teams = [0, 1].map(() =>
            [0, 1, 2].map((p) => {
              const c = rng.pick(CARDS);
              return u(
                c.id,
                3 + rng.int(8),
                rng.pick(GEARS).id,
                rng.pick(plans(c.id, p)),
              );
            }),
          ) as [Unit[], Unit[]];
          const result = battle(teams, [FIELDS[a].id, FIELDS[b].id]);
          expect(
            result.powers.flat().every((n) => Number.isFinite(n) && n >= 0),
          ).toBe(true);
        }
  });
  it("delayed transfers amplify once on receipt, not once when stored and again when paid", () => {
    const own = [
      u("GL3", 6, null, {
        on: true,
        targets: [{ side: "ally", pos: 1 }],
        mode: 0,
      }),
      u(),
      u(),
    ];
    expect(battle([own, neutral()], ["F1", "F5"]).powers[0]).toEqual([
      4, 11, 6,
    ]);
  });
  it("a tied auction disables only the new field and never the opening field", () => {
    const t = placed(21);
    passiveRound(t);
    for (const s of [0, 1] as const) t.act(s, { type: "operate", buy: false });
    const initial = t.stacks.slice();
    t.act(0, { type: "bid", yes: true, amount: 2 });
    t.act(1, { type: "bid", yes: false, amount: 2 });
    expect(t.effects[0].active).toBe(true);
    expect(t.effects[1].active).toBe(false);
    expect(t.stacks).toEqual(initial.map((n) => n - 2));
    expect(t.phase).toBe("plan");
  });
  it("has fourteen simple, four C1, four C2 and one C3 for every sin", () => {
    expect(
      ["S", "C1", "C2", "C3"].map(
        (g) => CARDS.filter((c) => c.grade === g).length,
      ),
    ).toEqual([14, 4, 4, 7]);
    expect(
      new Set(
        CARDS.filter((c) => c.grade === "C3").map((c) => sinOf(c.id).name),
      ).size,
    ).toBe(7);
    expect(CARDS.filter((c) => c.basic).length).toBeGreaterThanOrEqual(15);
  });
  it("does not reveal a disabled skill category", () => {
    expect(signal(u("WR4"))).toEqual({ on: false, kind: "off", targets: [] });
  });
  it("splits equal lanes without a hidden sum tie breaker", () => {
    expect(battle([neutral(), neutral()]).winner).toBeNull();
  });
  it("active skills do nothing when off", () => {
    const off = battle([[u("WR1"), u(), u()], neutral()]);
    expect(off.powers[1]).toEqual([6, 6, 6]);
  });
  it("shield does not forgive a friendly skill cost", () => {
    const a = u("WR2", 6, "G04", {
      on: true,
      targets: [{ side: "ally", pos: 1 }],
      mode: 0,
    });
    const b = battle([[a, u(), u()], neutral()]);
    expect(b.powers[0][0]).toBe(4);
    expect(b.powers[0][1]).toBe(10);
  });
  it("blocked drain cannot generate stolen force", () => {
    const a = u("GL1", 6, null, {
      on: true,
      targets: [{ side: "enemy", pos: 0 }],
      mode: 0,
    });
    const b = battle([
      [a, u(), u()],
      [u("EN3", 6, "G05"), u(), u()],
    ]);
    expect(b.powers[0][0]).toBe(6);
  });
  it("source amplification affects support and self reinforcement consistently", () => {
    for (const [id, plan] of [
      ["WR2", { on: true, targets: [{ side: "ally", pos: 1 }], mode: 0 }],
      ["WR3", { on: true, targets: [], mode: 0 }],
    ] as const) {
      const own = [
        u(id, 7, "G01", structuredClone(plan) as Unit["plan"]),
        u(),
        u(),
      ];
      const full = battle([own, neutral()]),
        base = battle([own, neutral()], [], { gearEffects: false });
      expect(
        full.powers[0].reduce((a, b) => a + b, 0) -
          base.powers[0].reduce((a, b) => a + b, 0),
      ).toBe(1);
    }
  });
  it("no paid offer can be abandoned or refunded", () => {
    const t = placed();
    passiveRound(t);
    const before = t.stacks[0];
    t.act(0, { type: "operate", buy: true });
    expect(t.stacks[0]).toBe(before - 2);
    expect(() => t.act(0, { type: "operate", buy: false })).toThrow();
    t.act(0, { type: "equip", offer: 0, pos: 0 });
    expect(t.observe(1).foe.equipment).toEqual([null, null, null]);
    t.act(1, { type: "operate", buy: false });
    expect(t.observe(1).foe.equipment[0]).not.toBeNull();
  });
  it("publishes plans together and rejects repeated submissions", () => {
    const t = placed(),
      selected = t.units[0]!.map((v, p) => plans(v.id, p).find((x) => x.on)!);
    t.act(0, { type: "plan", plans: selected });
    expect(t.observe(1).foe.signals.every((s) => !s.on)).toBe(true);
    expect(() => t.act(0, { type: "plan", plans: selected })).toThrow();
    t.act(1, { type: "plan", plans: [OFF(), OFF(), OFF()] });
    expect(t.observe(1).foe.signals.every((s) => s.on)).toBe(true);
  });
  it("has exactly three non-transferable equipment windows and locks every configuration", () => {
    const t = placed();
    let windows = 0;
    while (!t.result) {
      const s = t.actors()[0];
      if (t.phase.includes("plan"))
        t.act(s, { type: "plan", plans: [OFF(), OFF(), OFF()] });
      else if (t.phase === "bet") {
        if (t.round === 4)
          expect(() =>
            t.act(s, { type: "plan", plans: [OFF(), OFF(), OFF()] }),
          ).toThrow();
        t.act(s, { type: "check" });
      } else if (t.phase === "operate") {
        if (s === 0) windows++;
        t.act(s, { type: "operate", buy: false });
      } else if (t.phase === "bid")
        t.act(s, { type: "bid", yes: false, amount: 0 });
      else throw Error(t.phase);
    }
    expect(windows).toBe(3);
    expect(t.round).toBe(4);
    expect(t.spent).toBe(0);
  });
  it("early all-in does not grant equipment or a final plan change", () => {
    const t = placed();
    for (const s of [0, 1] as const)
      t.act(s, { type: "plan", plans: [OFF(), OFF(), OFF()] });
    t.act(t.turn, { type: "raise", to: 98 });
    t.act(t.turn, { type: "call" });
    expect(t.result).not.toBeNull();
    expect(t.round).toBe(1);
    expect(t.spent).toBe(0);
  });
  it("draws character instances with replacement", () => {
    let found = false;
    for (let seed = 1; seed < 20; seed++) {
      const t = new IntentTable(seed);
      if (new Set(t.offers[0]).size < 9) found = true;
    }
    expect(found).toBe(true);
  });
  it("allows selecting and independently planning two copies from the nine offers", () => {
    const t = new IntentTable(9);
    t.offers[0] = [
      "WR4",
      "WR4",
      "GR4",
      "WR1",
      "WR2",
      "WR3",
      "GR1",
      "GR2",
      "GR3",
    ];
    t.act(0, { type: "draft", indices: [0, 1, 2] });
    t.act(1, { type: "draft", indices: [0, 1, 2] });
    for (const s of [0, 1] as const)
      t.act(s, { type: "place", units: [0, 1, 2], numbers: [0, 1, 2] });
    expect(t.units[0]!.slice(0, 2).map((x) => x.id)).toEqual(["WR4", "WR4"]);
    const on = plans("WR4", 0).find((p) => p.on)!;
    t.act(0, { type: "plan", plans: [on, OFF(), OFF()] });
    t.act(1, { type: "plan", plans: [OFF(), OFF(), OFF()] });
    expect(t.units[0]![0].plan.on).toBe(true);
    expect(t.units[0]![1].plan.on).toBe(false);
    expect(t.units[0]![0]).not.toBe(t.units[0]![1]);
  });
  it("terminates and conserves chips in seeded full state-machine hands", () => {
    for (let seed = 11; seed < 14; seed++) {
      const t = new IntentTable(seed),
        bots = [new Bot(seed + 100), new Bot(seed + 200, "pressure")];
      let actions = 0;
      while (!t.result) {
        const s = t.actors()[0];
        t.act(s, bots[s].decide(t.observe(s)).action);
        if (++actions > 250) throw Error("Nontermination");
      }
      expect(t.stacks[0] + t.stacks[1] + t.spent).toBe(200);
    }
  }, 30000);
  it("duplicate complex skills and every equipment terminate deterministically", () => {
    const rng = new Rng(81);
    for (const c of CARDS.filter((c) => c.grade === "C3"))
      for (const g of GEARS) {
        const teams = [0, 1].map(() =>
          [0, 1, 2].map((p) =>
            u(c.id, 3 + rng.int(8), g.id, rng.pick(plans(c.id, p))),
          ),
        ) as [Unit[], Unit[]];
        const one = battle(teams, [
            "F1",
            "F2",
            "F3",
            "F4",
            "F5",
            "F6",
            "F7",
            "F8",
          ]),
          two = battle(teams, ["F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8"]);
        expect(one).toEqual(two);
        expect(one.powers.flat().every(Number.isFinite)).toBe(true);
      }
  });
});
