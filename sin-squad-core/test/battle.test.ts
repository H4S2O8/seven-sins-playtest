import { describe, expect, it } from "vitest";
import { runBattle } from "../src/battle/engine.js";
import { randomBattle } from "../src/sim/sampler.js";
import { Rng } from "../src/rng.js";
import { battle, hpAfter, team } from "./helpers.js";

describe("形状克制环", () => {
  it("效果槽牌会按新版攻/血面板参与战斗", () => {
    const base = battle(team(["GR3", null, null]), team(["SL1", null, null]));
    const boosted = battle({ ...team(["GR3", null, null]), slots: [{ characterId: "GR3", equipmentId: null, effectId: "FX01" }, { characterId: null, equipmentId: null }, { characterId: null, equipmentId: null }] }, team(["SL1", null, null]));
    expect(boosted.timeline[0][0][0].atk).toBe(base.timeline[0][0][0].atk + 2);
  });

  it("重击打护甲：每下减去护甲", () => {
    const r = battle(team(["GR3", null, null]), team(["SL1", null, null]));
    expect(hpAfter(r, 1, 1, 0)).toBe(11); // 收藏家 4 − 护甲 1
    expect(hpAfter(r, 1, 0, 0)).toBe(11); // 瞌睡客 1
  });

  it("护甲克连击：每段都被减，但整次攻击至少扣 1", () => {
    const low = battle(team(["WR1", null, null]), team(["SL1", null, null]));
    expect(hpAfter(low, 1, 1, 0)).toBe(13); // 两段各 1，全被护甲吃掉，补到 1

    const multi = battle(team(["WR1", null, null], ["E01"]), team(["SL1", null, null]));
    const heavy = battle(team(["WR2", null, null], ["E01"]), team(["SL1", null, null]));
    expect(hpAfter(multi, 1, 1, 0)).toBe(11); // 连击 5：2.5 + 2.5，各减 1 → 3
    expect(hpAfter(heavy, 1, 1, 0)).toBe(10); // 重击 5：5 − 1 → 4
  });

  it("屏障克重击、连击克屏障", () => {
    const vsHeavy = battle(team(["GR3", null, null]), team(["PR2", null, null]));
    expect(hpAfter(vsHeavy, 1, 1, 0)).toBe(8); // 整下被挡
    const vsMulti = battle(team(["WR1", null, null]), team(["PR2", null, null]));
    expect(hpAfter(vsMulti, 1, 1, 0)).toBe(7); // 第一段被挡，第二段打中
  });
});

describe("对位、转线与守护", () => {
  it("对位空着时，先花一轮转线", () => {
    const a = team(["GR3", null, null]);
    const b = team([null, "SL1", null]);
    const normal = battle(a, b);
    expect(hpAfter(normal, 1, 1, 1)).toBe(14);
    expect(hpAfter(normal, 2, 1, 1)).toBe(11);

    const arena02 = battle(a, b, { arenaId: "A02" }); // 圆形斗场：转线不花时间
    expect(hpAfter(arena02, 1, 1, 1)).toBe(11);

    const arena03 = battle(a, b, { arenaId: "A03" }); // 结冰渡口：转线要花两轮
    expect(hpAfter(arena03, 2, 1, 1)).toBe(14);
    expect(hpAfter(arena03, 3, 1, 1)).toBe(11);
  });

  it("守护：相邻队友受到的攻击改由同行药袋承受", () => {
    const r = battle(team(["GR3", null, null]), team(["WR2", "LU1", null]));
    expect(hpAfter(r, 1, 1, 0)).toBe(16);
    expect(hpAfter(r, 1, 1, 1)).toBe(18);
  });
});

describe("胜负判定", () => {
  it("同一轮同时全灭：比这一轮造成的伤害，相同则平局", () => {
    const draw = battle(team(["WR3", null, null]), team(["WR3", null, null]));
    expect(draw.winner).toBeNull();
    expect(draw.reason).toBe("平局");

    const win = battle(team(["WR3", null, null], ["E01"]), team(["WR3", null, null]));
    expect(win.winner).toBe(0);
    expect(win.rounds).toBe(1);
  });

  it("众目所向：击倒对方亮出的那名就赢，哪怕他还有人站着", () => {
    const r = battle(
      team(["WR3", null, "SL1"], [null, null, null], { revealedPos: 0 }),
      team(["SL1", null, "SL1"], [null, null, null], { revealedPos: 0 }),
      { ruleId: "V12" },
    );
    expect(r.winner).toBe(0);
    expect(r.reason).toBe("达成规则");
    expect(r.rounds).toBe(4);
    expect(r.final[1][2].alive).toBe(true);
  });

  it("限时规则按自带的回合数结束", () => {
    const r = battle(team(["LU1", null, null]), team(["LU1", null, null]), { ruleId: "V19" });
    expect(r.rounds).toBe(3);
  });
});

describe("开战时的能力", () => {
  it("夺装者拿走对位的装备；静默书库让它失效", () => {
    const a = team(["EN3", null, null]);
    const b = team(["GR3", null, null], ["E02"]);
    const stolen = battle(a, b);
    expect(stolen.timeline[0][0][0].startHp).toBe(22);
    expect(stolen.timeline[0][1][0].startHp).toBe(12);
    const silenced = battle(a, b, { arenaId: "A08" });
    expect(silenced.timeline[0][0][0].startHp).toBe(12);
    expect(silenced.timeline[0][1][0].startHp).toBe(22);
  });

  it("饕餮吞掉队友：得到它的攻和血，那个位置空出来", () => {
    const r = battle(team(["GL2", "SL1", null], [null, null, null], {}, { eater: 0, eaten: 1 }), team(["LU1", null, null]));
    const me = r.timeline[0][0];
    expect(me[0].atk).toBe(4);
    expect(me[0].startHp).toBe(26);
    expect(me[1].characterId).toBeNull();
  });

  it("下注层能力：金主按投入成长，挑衅者按对手加注成长", () => {
    const r = battle(
      team(["GR1", "WR1", null], [null, null, null], { invested: 35 }),
      team(["LU1", "LU1", null], [null, null, null], { betOrRaiseCount: 2 }),
    );
    const me = r.timeline[0][0];
    expect(me[0].atk).toBe(4); // 1 + 3
    expect(me[0].startHp).toBe(14); // 8 + 6
    expect(me[1].atk).toBe(6); // 2 + 2×2
  });
});

describe("确定性", () => {
  it("同样的输入永远得到同样的结果", () => {
    const rng = new Rng(42);
    for (let i = 0; i < 200; i++) {
      const { input } = randomBattle(rng);
      expect(runBattle(input)).toEqual(runBattle(input));
    }
  });

  it("随机战斗全部能正常结束", () => {
    const rng = new Rng(9);
    for (let i = 0; i < 3000; i++) {
      const r = runBattle(randomBattle(rng).input);
      expect(r.rounds).toBeGreaterThan(0);
      expect(r.rounds).toBeLessThanOrEqual(12);
    }
  });
});
