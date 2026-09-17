import test from "node:test";
import assert from "node:assert/strict";
import { UNITS, CARDS, RULES, PLEDGES, EFFECTS } from "../content.js";
import {
  makeUnit,
  newGame,
  auctionResult,
  ruleContest,
  createBattle,
  stepBattle,
  simulate,
  snapshot,
  resolveRule,
  pledgeMet,
  applyEffect,
  settle,
  autoDeploy,
  validDeployment,
  population,
  availableRules,
  rng,
  shuffle,
  living,
  stats,
} from "../engine.js";
const placed = (id, side, slot, mode = "move") => ({
  ...makeUnit(id, `${side}-${id}`),
  slot,
  mode,
});
test("exact catalog counts and unique IDs, actual implemented effects", () => {
  assert.deepEqual(
    [UNITS.length, CARDS.length, RULES.length, PLEDGES.length],
    [30, 50, 50, 50],
  );
  const ids = [...UNITS, ...CARDS, ...RULES, ...PLEDGES].map((x) => x.id);
  assert.equal(new Set(ids).size, 180);
  for (const c of CARDS) {
    assert.ok(EFFECTS[c.success]);
    assert.ok(EFFECTS[c.failure]);
    assert.notEqual(c.success, c.failure);
  }
  for (const p of PLEDGES) assert.ok(EFFECTS[p.reward]);
});
test("auction only winner pays; priority rotates only on ties", () => {
  assert.deepEqual(auctionResult([3, 5], 0), {
    winner: 1,
    cost: 5,
    priority: 0,
  });
  assert.deepEqual(auctionResult([0, 0], 0), {
    winner: 0,
    cost: 0,
    priority: 1,
  });
  assert.deepEqual(auctionResult([2, 2], 1), {
    winner: 1,
    cost: 2,
    priority: 0,
  });
  assert.throws(() => auctionResult([-1, 0], 0));
  assert.throws(() => auctionResult([0.5, 0], 0));
});
test("same nomination is free regardless of proposed bids", () => {
  assert.deepEqual(ruleContest(["r1", "r1"], [20, 30], 0), {
    rule: "r1",
    winner: null,
    cost: 0,
    priority: 0,
  });
  assert.equal(ruleContest(["r1", "r2"], [0, 1], 0).rule, "r2");
});
test("deployment cap and unique occupied slots", () => {
  assert.ok(validDeployment([placed("u1", 0, 0), placed("u5", 0, 4)]));
  assert.ok(
    !validDeployment([
      placed("u5", 0, 0),
      placed("u7", 0, 1),
      placed("u3", 0, 2),
    ]),
  );
  assert.ok(!validDeployment([placed("u1", 0, 0), placed("u2", 0, 0)]));
});
test("stationary charge never moves or charges; mobile charge attacks", () => {
  const b = createBattle([
    [placed("u2", 0, 4, "stand")],
    [placed("u12", 1, 4, "stand")],
  ]);
  for (let i = 0; i < 400 && !b.ended; i++) stepBattle(b);
  assert.equal(b.entities[0].x, 156);
  assert.equal(b.entities[0].chargeUsed, false);
  const c = simulate([[placed("u2", 0, 1)], [placed("u12", 1, 1)]]).battle;
  assert.ok(c.entities[0].chargeUsed);
  assert.ok(c.metrics[0].damage > 0);
});
test("battle deterministic including simultaneous tick ordering", () => {
  const us = [
    [placed("u6", 0, 4, "stand"), placed("u1", 0, 1)],
    [placed("u2", 1, 1), placed("u4", 1, 4, "stand")],
  ];
  assert.deepEqual(simulate(us).metrics, simulate(us).metrics);
});
test("all fifty rules resolve ties as success and read real snapshot keys", () => {
  const metrics = simulate([
    [placed("u1", 0, 1)],
    [placed("u1", 1, 1)],
  ]).metrics;
  for (const r of RULES) {
    assert.ok(Number.isFinite(metrics[0][r.metric]), r.metric);
    assert.deepEqual(resolveRule(r, [metrics[0], metrics[0]]), [true, true]);
    const a = { ...metrics[0], [r.metric]: 1 },
      b = { ...metrics[1], [r.metric]: 5 };
    assert.deepEqual(
      resolveRule(r, [a, b]),
      r.direction === 1 ? [false, true] : [true, false],
    );
  }
});
test("pledges have correct boundaries", () => {
  for (const p of PLEDGES) {
    assert.ok(pledgeMet(p, { [p.metric]: p.threshold }));
    assert.equal(pledgeMet(p, { [p.metric]: p.threshold + p.direction }), true);
    assert.equal(
      pledgeMet(p, { [p.metric]: p.threshold - p.direction }),
      false,
    );
  }
});
test('visually equal rule values resolve as equal instead of invisible differences',()=>{assert.deepEqual(resolveRule(RULES[0],[{markHp:33.321},{markHp:33.329}]),[true,true]);});
test("healing does not revive, dead target falls back to living unit", () => {
  const side = { units: [makeUnit("u1", "a"), makeUnit("u2", "b")] };
  side.units[0].hp = 0;
  side.units[1].hp = 10;
  assert.deepEqual(applyEffect(side, "mend", "a"), ["b"]);
  assert.equal(side.units[0].hp, 0);
  assert.equal(side.units[1].hp, 40);
});
test("buffs refresh rather than infinitely stack; future effects change stats", () => {
  const u = makeUnit("u3", "a"),
    side = { units: [u] };
  applyEffect(side, "fury", "a");
  applyEffect(side, "fury", "a");
  assert.equal(u.buffs.length, 1);
  assert.ok(stats(u).atk > 9);
  applyEffect(side, "moon", "a");
  assert.equal(stats(u).shields, 1);
});
test("snapshot before healing; old bench buffs expire; terminal victory after resolution", () => {
  const g = newGame(1);
  g.sides[0].units = [makeUnit("u1", "0-u1"), makeUnit("u3", "bench")];
  g.sides[1].units = [makeUnit("u2", "1-u2")];
  g.sides[0].cards = ["c4"];
  g.selectedCards = ["c4", null];
  g.rule = "r1";
  g.sides[0].units[1].buffs = [{ key: "fury", left: 1 }];
  const b = createBattle([[placed("u1", 0, 1)], [placed("u2", 1, 1)]]);
  b.entities[0].hp = 10;
  b.entities[1].hp = 60;
  const result = settle(g, b, ["0-u1"]);
  assert.equal(result.outcomes[0], false);
  assert.equal(g.sides[0].units[0].hp, 40);
  assert.equal(g.sides[0].units[1].buffs.length, 0);
  assert.equal(g.cardReady[0].c4, 3);
  assert.equal(g.winner, null);
});
test("filtered rules do not offer non-existent pull/healing/guard", () => {
  const us = [[placed("u3", 0, 1)], [placed("u3", 1, 1)]];
  for (let i = 0; i < 10; i++) {
    const rs = availableRules(us, rng(i));
    assert.equal(rs.length, 10);
    assert.ok(
      rs.every(
        (r) =>
          !["pull", "healing", "guarded", "push", "shield"].includes(r.metric),
      ),
    );
  }
});
test("all 30 units function in combat; every metric stays finite", () => {
  for (const u of UNITS) {
    const { battle, metrics } = simulate([
      [placed(u.id, 0, 1)],
      [placed("u1", 1, 1), placed("u9", 1, 4, "stand")],
    ]);
    assert.ok(battle.ended, u.id);
    for (const m of metrics)
      for (const n of Object.values(m)) assert.ok(Number.isFinite(n), u.id);
    assert.ok(metrics[0].hits > 0 || metrics[0].healing > 0, u.id);
  }
});
test("twenty seeded full matches reach roster elimination without a fixed round cap", () => {
  const lengths = [];
  for (let seed = 1; seed <= 20; seed++) {
    const rand = rng(seed);
    const us = shuffle(UNITS, rand).slice(0, 10),
      g = newGame(seed);
    for (let side = 0; side < 2; side++) {
      g.sides[side].units = us
        .slice(side * 5, side * 5 + 5)
        .map((u) => makeUnit(u.id, `${side}-${u.id}`));
      g.sides[side].cards = shuffle(CARDS, rand)
        .slice(0, 5)
        .map((c) => c.id);
      g.sides[side].pledges = shuffle(PLEDGES, rand)
        .slice(0, 5)
        .map((c) => c.id);
    }
    let round = 1;
    for (; round <= 55 && g.winner === null; round++) {
      g.round = round;
      g.deployed = g.sides.map((s) => autoDeploy(s, 6));
      assert.ok(g.deployed.every((d) => validDeployment(d)));
      g.selectedCards = g.sides.map((s, i) =>
        s.cards.find((id) => (g.cardReady[i][id] || 0) <= round),
      );
      g.selectedPledges = g.sides.map((s) => s.pledges[0] || null);
      g.rule = availableRules(g.deployed, rand)[0].id;
      const b = simulate(g.deployed, {round}).battle;
      settle(
        g,
        b,
        g.deployed.map((d) => d[0].uid),
      );
    }
    assert.notEqual(g.winner, null, `seed ${seed} stalled after ${round}`);
    lengths.push(round - 1);
  }
  console.log("20 complete match lengths", lengths.join(","));
});
