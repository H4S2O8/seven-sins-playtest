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
