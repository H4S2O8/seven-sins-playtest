import { describe, it, expect } from "vitest";
import { IntentSession } from "../src/intent/session.js";
import { IntentTable } from "../src/intent/table.js";
import { battle } from "../src/intent/battle.js";
import {
  analyse,
  compactAnalysis,
  publicAnalysis,
  planText,
} from "../src/intent/analysis.js";
import { CARDS, GEARS, plans } from "../src/intent/content.js";
import {
  OFF,
  type Action,
  type Observation,
  type Unit,
} from "../src/intent/types.js";

function prepare(s: IntentSession) {
  for (const seat of [0, 1] as const)
    s.act(seat, { type: "draft", indices: [0, 1, 2] });
  for (const seat of [0, 1] as const)
    s.act(seat, { type: "place", units: [0, 1, 2], numbers: [0, 1, 2] });
}
const off = (): Action => ({ type: "plan", plans: [OFF(), OFF(), OFF()] });
function passive(s: IntentSession) {
  const t = s.table,
    seat = t.actors()[0];
  if (t.phase.includes("plan")) s.act(seat, off());
  else if (t.phase === "bet")
    s.act(seat, { type: t.target > t.paid[seat] ? "call" : "check" });
  else if (t.phase === "operate") s.act(seat, { type: "operate", buy: false });
  else if (t.phase === "bid")
    s.act(seat, { type: "bid", yes: false, amount: 0 });
  else throw Error(t.phase);
}

describe("single-field game integration", () => {
  it("replaces the current field and a later tied auction preserves that replacement", () => {
    const s = new IntentSession(215);
    prepare(s);
    for (let round = 1; round <= 3; round++) {
      while (s.table.phase !== "bid") passive(s);
      s.act(0, { type: "bid", yes: true, amount: round === 1 ? 1 : 0 });
      s.act(1, { type: "bid", yes: false, amount: 0 });
      expect(s.table.effects.filter((f) => f.active).map((f) => f.id)).toEqual([
        s.table.effects[1].id,
      ]);
      expect(
        s.table
          .observe(0)
          .effects.slice(round + 1)
          .every((f) => f.id === null),
      ).toBe(true);
    }
  });
  it("restores private paid equipment offers and pending plans by replay", () => {
    const s = new IntentSession(91);
    prepare(s);
    s.act(0, off());
    expect(IntentSession.restore(s.save()).table.observe(1)).toEqual(
      s.table.observe(1),
    );
    while (s.table.phase !== "operate") passive(s);
    s.act(0, { type: "operate", buy: true });
    const restored = IntentSession.restore(
      JSON.parse(JSON.stringify(s.save())),
    );
    expect(restored.table.observe(0)).toEqual(s.table.observe(0));
    restored.act(0, { type: "equip", offer: 2, pos: 1 });
    s.act(0, { type: "equip", offer: 2, pos: 1 });
    expect(restored.table.observe(0)).toEqual(s.table.observe(0));
  });
  it("preserves chips between hands and keeps folded identities hidden", () => {
    const s = new IntentSession(41);
    prepare(s);
    while (s.table.phase !== "bet") passive(s);
    s.act(s.table.actors()[0], { type: "fold" });
    expect(s.table.result!.teams).toBeUndefined();
    const next = s.next(42);
    expect(next.table.stacks[0] + next.table.stacks[1] + next.table.pot).toBe(
      200,
    );
    expect(next.hand).toBe(2);
  });
  it("reveals actual units only at showdown and analysis matches the resolver", () => {
    const s = new IntentSession(55);
    prepare(s);
    while (!s.table.result) passive(s);
    const a = analyse(s.table.observe(0))!;
    expect(a.kind).toBe("actual");
    expect(a.battle.powers).toEqual(s.table.result!.battle!.powers);
    const other = analyse(s.table.observe(1))!;
    expect(other.battle.powers[0]).toEqual(s.table.result!.battle!.powers[1]);
  });
  it("handles a short stack ante without a zero-stack betting deadlock", () => {
    const s = new IntentSession(44, 2, [0.5, 199.5]);
    prepare(s);
    s.act(0, off());
    s.act(1, off());
    expect(s.table.result).not.toBeNull();
    expect(s.table.stacks[0] + s.table.stacks[1]).toBe(200);
  });
  it("allows a fractional all-in and zero bid with less than one spare chip", () => {
    const s = new IntentSession(44, 2, [2.5, 197.5]);
    prepare(s);
    while (s.table.phase !== "bet") passive(s);
    if (s.table.actors()[0] === 1) s.act(1, { type: "check" });
    s.act(0, { type: "raise", to: 0.5 });
    s.act(1, { type: "call" });
    expect(s.table.result).not.toBeNull();
    const t = new IntentTable(51);
    t.phase = "bid";
    t.revealedEffects = 2;
    t.stacks = [0.5, 100];
    t.act(0, { type: "bid", yes: true, amount: 0 });
    t.act(1, { type: "bid", yes: false, amount: 0 });
    expect(t.phase).toBe("plan");
  });
  it("does not leak pending enemy configurations or future fields through analysis", () => {
    const s = new IntentSession(992);
    prepare(s);
    const o = s.table.observe(0);
    const a = analyse(o);
    s.table.plans[1] = s.table.units[1]!.map((u, p) => plans(u.id, p).at(-1)!);
    s.table.effects[3].id = s.table.effects[3].id === "F1" ? "F8" : "F1";
    expect(analyse(s.table.observe(0))).toEqual(a);
    expect(JSON.stringify(o)).not.toContain('seedLabel":992');
  });
  it("explains every character and equipment using natural language instead of compressed notation", () => {
    const s = new IntentSession(832);
    prepare(s);
    const o = s.table.observe(0);
    for (let i = 0; i < Math.max(CARDS.length, GEARS.length); i++) {
      const c = CARDS[i % CARDS.length],
        own: Unit[] = [
          {
            id: c.id,
            raw: 8,
            gear: GEARS[i % GEARS.length].id,
            plan: plans(c.id, 0).at(-1)!,
          },
          ...o.me.units!.slice(1),
        ];
      const a = analyse(o, own)!;
      for (let p = 0; p < 3; p++) {
        const text = compactAnalysis(a, p);
        expect(text).toMatch(/^本例/);
        expect(text).toContain(`最终力量为${a.units[p].final}`);
        expect(text).not.toMatch(/装[123]|场[123]|→|\d\/\d/);
      }
    }
  });
  it("uses the full public equipment rule without guessing hidden skills", () => {
    const s = new IntentSession(99);
    prepare(s);
    const o = s.table.observe(0);
    for (const g of GEARS) {
      o.foe.equipment[0] = g.id;
      expect(publicAnalysis(o, 0)).toContain(g.name);
      expect(publicAnalysis(o, 0)).toContain(g.text);
      expect(publicAnalysis(o, 0)).toContain("不能确定最终输出");
    }
    expect(
      planText(
        "WR2",
        { on: true, mode: 0, targets: [{ side: "ally", pos: 1 }] },
        true,
      ),
    ).toBe("发动 → 敌2位");
  });
  it("names the recipient, equipment and field in the played support combination", () => {
    const s = new IntentSession(99);
    prepare(s);
    const o = s.table.observe(0);
    const own: Unit[] = [
      {
        id: "WR3",
        raw: 3,
        gear: null,
        plan: { on: true, mode: 0, targets: [] },
      },
      { id: "WR3", raw: 6, gear: null, plan: OFF() },
      {
        id: "WR2",
        raw: 9,
        gear: "G12",
        plan: { on: true, mode: 0, targets: [{ side: "ally", pos: 1 }] },
      },
    ];
    const foe: Unit[] = Array.from({ length: 3 }, () => ({
      id: "WR3",
      raw: 6,
      gear: null,
      plan: OFF(),
    }));
    o.initiative = 0;
    o.effects = [{ id: "F4", active: true }];
    o.me.units = own;
    const resolved = battle([own, foe], ["F4"]);
    o.result = {
      fold: false,
      winner: resolved.winner,
      battle: resolved,
      teams: [own, foe],
      payouts: [0, 0],
    };
    const text = compactAnalysis(analyse(o)!, 2);
    expect(text).toBe(
      "本次支付4点力量，向中位送出9点强化，最终力量为5。聚焦镜使中位多3点力量。代价熔炉使左位多4点、中位多2点力量。",
    );
    expect(text.length).toBeGreaterThan(50);
  });
});
