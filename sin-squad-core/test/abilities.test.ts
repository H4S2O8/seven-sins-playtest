import { describe, expect, it } from "vitest";
import { runBattle, splitMulti } from "../src/battle/engine.js";
import { character } from "../src/content/characters.js";
import { randomBattle } from "../src/sim/sampler.js";
import { Rng } from "../src/rng.js";
import { afterHit, battle, team } from "./helpers.js";

/** 这一场里某个能力有没有发动过。 */
const fired = (r: ReturnType<typeof battle>, name: string) => r.events.some((e) => e.type === "trigger" && e.name === name);
const solo = (id: string, b = {}) => team([id, null, null], [null, null, null], b);
/** 人物卡面上的攻 / 血 / 护甲（测试不写死身材，调数值时不用跟着改）。 */
const atk = (id: string) => character(id).atk;
const hp = (id: string) => character(id).hp;
const arm = (id: string) => character(id).armor;
/** 一次攻击打在护甲上的伤害（连击每段减护甲，整次至少 1）。 */
const dealt = (id: string, d: number, armor: number) => {
  const parts = character(id).shape === "multi" ? splitMulti(d) : [d];
  return Math.max(1, parts.reduce((s, p) => s + Math.max(0, p - armor), 0));
};
/** 随机一场（双方随机 3 人、随机规则场地），直接打完。 */
const randomRun = (rng: Rng) => runBattle(randomBattle(rng).input);

describe("第二批人物", () => {
  it("金库守卫：开战时筹码领先才得屏障", () => {
    expect(battle(solo("GR4", { stack: 80 }), solo("GR2", { stack: 60 })).start[0][0].barrier).toBe(1);
    expect(battle(solo("GR4", { stack: 60 }), solo("GR2", { stack: 80 })).start[0][0].barrier).toBe(0);
  });

  it("双子：站在 2 号位、两侧都有队友，全队血 +2", () => {
    const mid = battle(team(["GR1", "LU5", "GL3"]), solo("GR2")).start[0];
    expect(mid.map((u) => u.hp)).toEqual([hp("GR1") + 2, hp("LU5") + 2, hp("GL3") + 2]);
    const side = battle(team(["LU5", "GR1", "GL3"]), solo("GR2")).start[0];
    expect(side.map((u) => u.hp)).toEqual([hp("LU5"), hp("GR1"), hp("GL3")]);
  });

  it("影子：打被亮出的敌人攻 +2", () => {
    const seen = battle(solo("EN4"), team(["GR4", null, null], [null, null, null], { revealedPos: 0 }));
    const hidden = battle(solo("EN4"), team(["GR4", null, null], [null, null, null], { revealedPos: 1 }));
    expect(afterHit(seen, 1)[1][0].hp).toBe(hp("GR4") - dealt("EN4", atk("EN4") + 2, arm("GR4")));
    expect(afterHit(hidden, 1)[1][0].hp).toBe(hp("GR4") - dealt("EN4", atk("EN4"), arm("GR4")));
  });

  it("大野狼：敌方只剩一人时攻 +4", () => {
    expect(afterHit(battle(solo("GL5"), solo("GR4")), 1)[1][0].hp).toBe(hp("GR4") - dealt("GL5", atk("GL5") + 4, arm("GR4")));
    expect(afterHit(battle(solo("GL5"), team(["GR4", "GR4", null])), 1)[1][0].hp).toBe(hp("GR4") - dealt("GL5", atk("GL5"), arm("GR4")));
  });

  it("守夜人：第三轮起才加攻", () => {
    const rng = new Rng(7);
    let seen = false;
    for (let i = 0; i < 400; i++) {
      for (const e of randomRun(rng).events) {
        if (e.type !== "trigger" || e.name !== "守夜人") continue;
        expect(e.round).toBeGreaterThanOrEqual(3);
        seen = true;
      }
    }
    expect(seen).toBe(true);
  });

  it("噬铁软泥：打中带护甲的人，腐蚀掉 1 点护甲（每人一次）", () => {
    const r = battle(solo("GL4"), solo("GR4"));
    expect(afterHit(r, 1)[1][0].armor).toBe(arm("GR4") - 1);
    expect(r.events.filter((e) => e.type === "trigger" && e.name === "噬铁软泥")).toHaveLength(1);
  });

  it("攻城锤手：第一次打破屏障，攻 +2（只一次）", () => {
    const r = battle(solo("WR4"), solo("PR2"));
    expect(fired(r, "攻城锤手")).toBe(true);
    expect(afterHit(r, 1)[0][0].atk).toBe(atk("WR4") + 2);
    expect(r.events.filter((e) => e.type === "trigger" && e.name === "攻城锤手")).toHaveLength(1);
  });

  it("交际花：打中它的敌人下一次攻击 -2（每个敌人一次）", () => {
    // 痴情骑士第一下被屏障挡掉；交际花出手时被它反击打中，它下一次攻击 -2
    const r = battle(solo("LU1"), team(["LU4", "GR4", null]));
    const flirts = r.events.filter((e) => e.type === "trigger" && e.name === "交际花");
    expect(flirts).toHaveLength(1);
    const sum = (e: (typeof r.events)[number] | undefined) => (e?.type === "attack" ? e.segments.reduce((s, x) => s + x, 0) : null);
    const next = r.events.slice(r.events.indexOf(flirts[0])).find((e) => e.type === "attack" && e.seat === 0);
    expect(sum(next)).toBe(atk("LU1") - 2);
  });

  it("全部人物混打几千场：不出错、血量和攻都是整数", () => {
    const rng = new Rng(2026);
    for (let i = 0; i < 3000; i++) {
      const r = randomRun(rng);
      for (const side of r.final) for (const u of side) {
        expect(Number.isInteger(u.hp)).toBe(true);
        expect(Number.isInteger(u.atk)).toBe(true);
      }
    }
  });
});
