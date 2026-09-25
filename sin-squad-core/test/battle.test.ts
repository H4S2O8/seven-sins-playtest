import { describe, expect, it } from "vitest";
import { runBattle } from "../src/battle/engine.js";
import { randomBattle } from "../src/sim/sampler.js";
import { Rng } from "../src/rng.js";
import { battle, hpAfter, team } from "./helpers.js";

describe("形状克制环", () => {
  it("重击打护甲：每下减去护甲", () => {
    const r = battle(team(["GR3", null, null]), team(["SL1", null, null]));
    expect(hpAfter(r, 1, 1, 0)).toBe(9 - 3); // 收藏家 4 − 护甲 1
    expect(hpAfter(r, 1, 0, 0)).toBe(7 - 1); // 瞌睡客 1
  });

  it("护甲克连击：每段都被减，但整次攻击至少扣 1", () => {
    const low = battle(team(["WR1", null, null]), team(["SL1", null, null]));
    expect(hpAfter(low, 1, 1, 0)).toBe(8); // 两段各 1，全被护甲吃掉，补到 1

    const multi = battle(team(["GR3", null, null], ["E07"]), team(["SL1", null, null]));
    const heavy = battle(team(["GR3", null, null]), team(["SL1", null, null]));
    expect(hpAfter(multi, 1, 1, 0)).toBe(9 - 2); // 连击 4：2 + 2，各减 1 → 2
    expect(hpAfter(heavy, 1, 1, 0)).toBe(9 - 3); // 重击 4：4 − 1 → 3
  });

  it("屏障克重击、连击克屏障", () => {
    const vsHeavy = battle(team(["GR3", null, null]), team(["PR2", null, null]));
    expect(hpAfter(vsHeavy, 1, 1, 0)).toBe(3); // 整下被挡
    const vsMulti = battle(team(["WR1", null, null]), team(["PR2", null, null]));
    expect(hpAfter(vsMulti, 1, 1, 0)).toBe(2); // 第一段被挡，第二段打中
  });
});

describe("对位、转线与守护", () => {
  it("对位空着时，先花一轮转线", () => {
    const a = team(["GR3", null, null]);
    const b = team([null, "SL1", null]);
    const normal = battle(a, b);
    expect(hpAfter(normal, 1, 1, 1)).toBe(9);
    expect(hpAfter(normal, 2, 1, 1)).toBe(6);

    const arena02 = battle(a, b, { arenaId: "A02" }); // 圆形斗场：转线不花时间
    expect(hpAfter(arena02, 1, 1, 1)).toBe(6);

    const arena03 = battle(a, b, { arenaId: "A03" }); // 结冰渡口：转线要花两轮
    expect(hpAfter(arena03, 2, 1, 1)).toBe(9);
    expect(hpAfter(arena03, 3, 1, 1)).toBe(6);
  });

  it("守护：相邻队友受到的攻击改由同行药袋承受", () => {
    const r = battle(team(["GR3", null, null]), team(["WR2", "LU1", null]));
    expect(hpAfter(r, 1, 1, 1)).toBe(12 - 4); // 收藏家的 4 打在药袋身上
    // 收藏家没在打蓄痛拳手，所以蓄痛拳手这一下是单向攻击，吃收藏家 4 点碰撞
    expect(hpAfter(r, 1, 1, 0)).toBe(10 - 4);
    // 药袋这一轮在转线、不出手，所以不反击；收藏家只吃蓄痛拳手的 1
    expect(hpAfter(r, 1, 0, 0)).toBe(7 - 1);
  });
});

describe("碰撞", () => {
  it("对位互打只算一次：双方各吃对方的攻", () => {
    const r = battle(team(["GR3", null, null]), team(["GR2", null, null]));
    expect(hpAfter(r, 1, 0, 0)).toBe(7 - 3);
    expect(hpAfter(r, 1, 1, 0)).toBe(8 - 4);
    expect(r.events.some((e) => e.type === "recoil")).toBe(false);
  });

  it("转线后打别人：被打的人把自己的攻打回来", () => {
    // 我方 1 号位对面是空的；转线一轮后去打盾税官（3/8），而盾税官正在打它的对位
    const r = battle(team(["GR3", "SL1", null]), team([null, "GR2", null]));
    expect(hpAfter(r, 1, 0, 0)).toBe(7); // 第 1 轮在转线
    expect(hpAfter(r, 2, 0, 0)).toBe(7 - 3); // 第 2 轮打盾税官，吃它 3 点碰撞
    expect(hpAfter(r, 2, 1, 1)).toBe(8 - 1 - 1 - 4);
    expect(r.events.some((e) => e.type === "recoil" && e.round === 2 && e.seat === 1 && e.amount === 3)).toBe(true);
  });

  it("屏障也挡碰撞", () => {
    const r = battle(team(["PR2", "SL1", null]), team([null, "GR2", null]));
    // 无瑕刺客 3/3 带 1 层屏障：第 2 轮打盾税官，盾税官的碰撞被屏障挡掉
    expect(hpAfter(r, 2, 0, 0)).toBe(3);
    expect(r.timeline[1][0][0].barrier).toBe(0);
  });

  it("这一轮不出手的人不反击", () => {
    // 沉眠巨像第一轮不出手：收藏家打它是单向攻击，但它不反击
    const r = battle(team(["GR3", null, null]), team(["SL2", null, null]));
    expect(hpAfter(r, 1, 0, 0)).toBe(7);
    expect(hpAfter(r, 1, 1, 0)).toBe(7 - 3);
    expect(hpAfter(r, 2, 0, 0)).toBe(7 - 3); // 第二轮醒来，正常互打
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
    expect(r.rounds).toBe(3); // 清算者每轮打掉 4，9 血撑到第 3 轮
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
    expect(stolen.start[0][0].startHp).toBe(7 + 6);
    expect(stolen.start[1][0].startHp).toBe(7);
    const silenced = battle(a, b, { arenaId: "A08" });
    expect(silenced.start[0][0].startHp).toBe(7);
    expect(silenced.start[1][0].startHp).toBe(7 + 6);
  });

  it("饕餮吞掉队友：得到它的攻和血，那个位置空出来", () => {
    const r = battle(team(["GL2", "SL1", null], [null, null, null], {}, { eater: 0, eaten: 1 }), team(["LU1", null, null]));
    const me = r.start[0];
    expect(me[0].atk).toBe(3 + 1);
    expect(me[0].startHp).toBe(8 + 9);
    expect(me[1].characterId).toBeNull();
  });

  it("下注层能力：金主按投入成长，挑衅者按对手加注成长", () => {
    const r = battle(
      team(["GR1", "WR1", null], [null, null, null], { invested: 35 }),
      team(["LU1", "LU1", null], [null, null, null], { betOrRaiseCount: 2 }),
    );
    const me = r.start[0];
    expect(me[0].atk).toBe(1 + 3);
    expect(me[0].startHp).toBe(5 + 3);
    expect(me[1].atk).toBe(2 + 2 * 2);
  });
});

describe("触发事件", () => {
  it("开战时和战斗中生效的能力都会记下来，给画面播放", () => {
    const r = battle(
      team(["PR1", "WR2", null], [null, null, null], { revealedPos: 0 }),
      team(["GR3", "GR2", null]),
    );
    const trig = r.events.filter((e) => e.type === "trigger");
    expect(trig).toContainEqual({ round: 0, type: "trigger", seat: 0, pos: 0, name: "炫耀者", text: "被亮出：+3/+4" });
    expect(trig.some((e) => e.round === 1 && e.name === "蓄痛拳手")).toBe(true);
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
