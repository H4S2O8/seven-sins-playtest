import { describe, expect, it } from "vitest";
import { unitFrom } from "../src/battle/unit.js";
import { instantClaims, setupVictory } from "../src/battle/victory.js";
import { campaignCard, campaignRoster } from "../src/content/campaign-cards.js";
import { character, CHARACTERS } from "../src/content/characters.js";
import { afterHit, battle, hpAfter, team } from "./helpers.js";

describe("炼狱业火", () => {
  // 牵线人把对位缔结住，双方谁都不出手，只能靠业火收尾
  const bonded = () => battle(team(["LU2", "LU2", "LU2"]), team(["LU1", "LU1", "LU1"]), { campaign: { hellfire: true } });

  it("从第 4 轮起每轮末烧一次，第 4 轮 1 点，之后每轮多 1", () => {
    const r = bonded();
    const fires = r.events.filter((e) => e.type === "hellfire");
    expect(fires.map((e) => [e.round, e.type === "hellfire" && e.amount])).toEqual([[4, 1], [5, 2], [6, 3], [7, 4]]);
    expect(hpAfter(r, 3, 0, 0)).toBe(7);
    expect(hpAfter(r, 6, 0, 0)).toBe(7 - 1 - 2 - 3);
  });

  it("战斗以有人全灭结束，不再到时比较", () => {
    const r = bonded();
    expect(r.reason).toBe("达成规则");
    expect(r.winner).toBe(1); // 牵线人 7 血先烧光，痴情骑士 12 血还站着
    expect(r.rounds).toBe(7);
  });

  it("不开业火时照旧到时比较", () => {
    const r = battle(team(["LU2", "LU2", "LU2"]), team(["LU1", "LU1", "LU1"]));
    expect(r.events.some((e) => e.type === "hellfire")).toBe(false);
    expect(r.reason).toBe("到时比较");
  });

  it("业火不经屏障", () => {
    const r = battle(team(["LU2", "LU2", "LU2"]), team(["LU4", "LU4", "LU4"]), { campaign: { hellfire: true } });
    expect(hpAfter(r, 4, 1, 0)).toBe(6 - 1);
    expect(r.timeline[3][1][0].barrier).toBe(1);
  });
});

describe("打最近的敌人", () => {
  const firstAttack = (r: ReturnType<typeof battle>, pos: number) =>
    r.events.find((e) => e.type === "attack" && e.seat === 0 && e.pos === pos);

  it("对位空着时不空过，第 1 轮就打最近的 2 号位", () => {
    const r = battle(team(["GR3", null, null]), team([null, "WR2", "GL3"]), { campaign: { nearest: true } });
    expect(r.events.some((e) => e.type === "switch")).toBe(false);
    const a = firstAttack(r, 0);
    expect(a && a.type === "attack" && a.round === 1 && a.targetPos).toBe(1);
  });

  it("2 号位打血较少的一翼", () => {
    const r = battle(team([null, "GR3", null]), team(["WR2", null, "GL3"]), { campaign: { nearest: true } });
    const a = firstAttack(r, 1);
    expect(a && a.type === "attack" && a.targetPos).toBe(2); // 食腐鸦 7 血 < 狂战士 10 血
  });

  it("2 号位倒了就往另一翼找", () => {
    const r = battle(team(["GR3", null, null]), team([null, null, "GL3"]), { campaign: { nearest: true } });
    const a = firstAttack(r, 0);
    expect(a && a.type === "attack" && a.targetPos).toBe(2);
  });

  it("不开时照旧先花一轮转线", () => {
    const r = battle(team(["GR3", null, null]), team([null, "WR2", null]));
    expect(r.events.some((e) => e.type === "switch")).toBe(true);
  });
});

describe("战役卡面", () => {
  it("护甲 1 换成血 +2", () => {
    const bear = campaignCard("SL1");
    expect([bear.hp, bear.armor]).toEqual([9 + 2, 0]);
    const r = battle(team(["SL1", null, null]), team([null, null, null]), { campaign: { cards: true } });
    expect([r.start[0][0].hp, r.start[0][0].armor]).toEqual([11, 0]);
  });

  it("赎罪券商按下注或加注次数得屏障", () => {
    const r = battle(team(["GR2", null, null], [], { betOrRaiseCount: 3 }), team([null, null, null]), { campaign: { cards: true } });
    expect(r.start[0][0].barrier).toBe(2);
  });

  it("隐修士：没下注或加注过才给全队血 +5", () => {
    const calm = battle(team(["SL3", "WR2", null]), team([null, null, null]), { campaign: { cards: true } });
    const bold = battle(team(["SL3", "WR2", null], [], { betOrRaiseCount: 1 }), team([null, null, null]), { campaign: { cards: true } });
    expect(calm.start[0][1].hp).toBe(15);
    expect(bold.start[0][1].hp).toBe(10);
  });

  it("噬铁软泥多打掉一层屏障", () => {
    // 赎罪券商下注两次，带 2 层屏障；软泥连击 1 + 2：第一段被挡并多剥一层，第二段打中
    const r = battle(team(["GL4", null, null]), team(["GR2", null, null], [], { betOrRaiseCount: 2 }), { campaign: { cards: true } });
    expect(r.start[1][0].barrier).toBe(2);
    const hit = afterHit(r, 1);
    expect([hit[1][0].barrier, hit[1][0].hp]).toEqual([0, 8 - 2]);
  });

  it("牌池按关卡解锁，扒手不进战役", () => {
    expect(campaignRoster(0)).toEqual(["WR2", "GR3", "GL1", "GL3", "SL4", "LU1", "GL5", "LU5"].sort((a, b) =>
      CHARACTERS.findIndex((c) => c.id === a) - CHARACTERS.findIndex((c) => c.id === b)));
    expect(campaignRoster(7)).toHaveLength(CHARACTERS.length - 1);
    expect(campaignRoster(7)).not.toContain("EN3");
    expect(campaignRoster(4)).not.toContain("PR2");
  });
});

describe("魔神降临", () => {
  it("第 1 轮不来，第 2 轮开始时补到编号最小的空位", () => {
    const r = battle(team([null, "WR2", null]), team(["GL3", "GL3", "GL3"]), { campaign: { demons: ["DM1", null] } });
    const d = r.events.filter((e) => e.type === "demon");
    expect(d).toHaveLength(1);
    expect(d[0]).toMatchObject({ round: 2, seat: 0, pos: 0, characterId: "DM1" });
    expect(r.timeline[1][0][0]).toMatchObject({ characterId: "DM1", demon: true });
  });

  it("第 2 轮起一有空位就降临，这一轮还会出手", () => {
    // 食腐鸦第 2 轮被痴情骑士打倒，魔神当轮补上，排到本方最后出手
    const r = battle(team(["LU2", "GL3", "LU2"]), team(["LU2", "LU1", "LU2"]), { campaign: { demons: ["DM1", null] } });
    const i = r.events.findIndex((e) => e.type === "demon");
    expect(r.events[i]).toMatchObject({ round: 2, seat: 0, pos: 1 });
    expect(r.events.slice(i).some((e) => e.type === "attack" && e.round === 2 && e.seat === 0 && e.pos === 1)).toBe(true);
  });

  it("每场只来一次", () => {
    const r = battle(team([null, null, "WR2"]), team(["GL3", "GL3", "GL3"]), { campaign: { demons: ["DM1", "DM2"] } });
    expect(r.events.filter((e) => e.type === "demon" && e.seat === 0)).toHaveLength(1);
  });

  it("被魔神顶掉位置的倒下者照样算击倒数", () => {
    const mk = (ids: string[], seat: 0 | 1) => ids.map((id, pos) => unitFrom(character(id), seat, pos));
    const teams: [ReturnType<typeof mk>, ReturnType<typeof mk>] = [mk(["WR2", "WR2", "WR2"], 0), mk(["GL3", "GL3", "GL3"], 1)];
    const st = setupVictory("V03", teams, [0, 0]);
    teams[0][0].alive = false;
    st.removedDead[0].push(teams[0][0]);
    teams[0][0] = unitFrom(character("DM1"), 0, 0);
    expect(instantClaims(st, teams)[1]).toBe(false);
    teams[0][1].alive = false;
    expect(instantClaims(st, teams)[1]).toBe(true);
  });

  it("魔神牌能按编号查到", () => {
    expect(character("DM6").name).toBe("万蝇之王");
  });
});

describe("七张魔神牌", () => {
  // 我方 1 号位空着，魔神第 2 轮开始时降临到 1 号位；对面三人都在
  const vs = (demon: string, foes: (string | null)[] = ["WR2", "GL3", "LU1"], mine: (string | null)[] = [null, "LU2", "LU2"]) =>
    battle(team(mine), team(foes), { campaign: { demons: [demon, null], nearest: true } });
  const after = (r: ReturnType<typeof battle>) => {
    const i = r.frames.findIndex((f) => f.events.some((e) => e.type === "demon"));
    return r.frames[i].after;
  };

  it("晨星：向攻最高的敌人下战书，只打它，守护也拦不住", () => {
    // 对面：狂战士 1 攻、清算者 5 攻、痴情骑士守护清算者
    const r = vs("DM1", ["WR2", "WR3", "LU1"]);
    expect(r.events.some((e) => e.type === "trigger" && e.name === "晨星" && e.text.includes("清算者"))).toBe(true);
    // 打倒清算者之前，她只打清算者；痴情骑士就在旁边也替不了
    const hits = r.events.filter((e) => e.type === "attack" && e.seat === 0 && e.pos === 0);
    const kill = r.events.findIndex((e) => e.type === "death" && e.seat === 1 && e.pos === 1);
    const before = hits.filter((h) => r.events.indexOf(h) < kill);
    expect(before.length).toBeGreaterThan(0);
    for (const h of before) expect(h.type === "attack" && h.targetPos).toBe(1);
    expect(r.events.slice(0, kill).some((e) => e.type === "trigger" && e.name === "痴情骑士")).toBe(false);
  });

  it("深渊之眼：降临时从每名敌人身上抢 1 点攻，最低留 1", () => {
    const snap = after(vs("DM2", ["WR2", "GL3", "LU1"]));
    expect(snap[1].map((u) => u.atk)).toEqual([1, 1, 2]); // 狂战士 1 攻不再减
    expect(snap[0][0].atk).toBe(2 + 2);
  });

  it("焚怒：出手打到所有敌人", () => {
    const r = vs("DM3");
    // 第 2 轮她出手一次：对三名敌人各打一下（打食腐鸦那一下被痴情骑士守护接走）
    const turn = r.events.filter((e) => e.type === "attack" && e.seat === 0 && e.pos === 0 && e.round === 2);
    expect(turn).toHaveLength(3);
  });

  it("永眠：从不出手，反击双倍", () => {
    const r = vs("DM4");
    expect(r.events.some((e) => e.type === "attack" && e.seat === 0 && e.pos === 0)).toBe(false);
    const back = r.events.find((e) => e.type === "recoil" && e.seat === 0 && e.pos === 0);
    expect(back && back.type === "recoil" && back.amount).toBe(6);
  });

  it("金山：降临收利息，每手最多 20", () => {
    const r = vs("DM5");
    expect(r.interest[0]).toBeGreaterThanOrEqual(5);
    expect(r.interest[0]).toBeLessThanOrEqual(20);
    expect(r.interest[1]).toBe(0);
    const quiet = battle(team(["WR2", null, null]), team(["WR2", null, null]));
    expect(quiet.interest).toEqual([0, 0]);
  });

  it("万蝇之王：降临后马上出手一次", () => {
    const r = vs("DM6");
    const i = r.events.findIndex((e) => e.type === "demon");
    const next = r.events.slice(i + 1).find((e) => e.type === "attack");
    expect(next).toMatchObject({ seat: 0, pos: 0 });
  });

  it("欲之王：和敌方血最多的人交换当前血量", () => {
    const snap = after(vs("DM7", ["WR2", "GL3", "LU1"]));
    expect(snap[0][0].hp).toBe(12); // 痴情骑士的 12 血
    expect(snap[1][2].hp).toBe(3);
  });
});

describe("关卡牌桌带上战役战斗规则", () => {
  it("stageTable 打开业火、打最近、战役卡面，双方带魔神", async () => {
    const { newProgress, stageTable } = await import("../src/campaign/progress.js");
    const p = newProgress();
    p.cleared = 3;
    p.demons = ["晨星", "深渊之眼"];
    const o = stageTable(p, 3, 1, "晨星");
    expect(o.campaign!.battle).toEqual({ hellfire: true, cards: true, nearest: true, demons: ["DM1", "DM3"] });
    expect(stageTable(p, 0, 1).campaign!.battle!.demons).toEqual([null, null]);
    expect(() => stageTable(p, 3, 1, "金山")).toThrow();
  });

  it("金山的利息在奖池分完后结算，筹码守恒", async () => {
    const { newProgress, stageTable } = await import("../src/campaign/progress.js");
    const { Table } = await import("../src/game/table.js");
    const { HeuristicAgent, playTable } = await import("../src/ai/agents.js");
    const p = newProgress();
    p.cleared = 6;
    p.demons = ["晨星", "深渊之眼", "焚怒", "永眠", "金山"];
    let seen = 0;
    for (let seed = 1; seed <= 30 && !seen; seed++) {
      const t = new Table(stageTable(p, 6, seed, "金山"));
      playTable(t, [new HeuristicAgent("cautious", seed, 4), new HeuristicAgent("aggressive", seed + 1, 4)]);
      for (const e of t.log) if (e.type === "interest") { seen++; expect(e.amount).toBeLessThanOrEqual(20); }
    }
    expect(seen).toBeGreaterThan(0);
  });
});
