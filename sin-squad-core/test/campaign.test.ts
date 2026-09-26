import { describe, expect, it } from "vitest";
import { HeuristicAgent, playTable, RandomAgent } from "../src/ai/agents.js";
import { applyReward, newProgress, recordLoss, recordWin, rewardOffer, stageTable, tauntTier, unlocked } from "../src/campaign/progress.js";
import { MIN_CAMPAIGN_POOL, STAGES, STARTING_POOL, stage } from "../src/campaign/stages.js";
import { campaignRoster } from "../src/content/campaign-cards.js";
import { CHARACTERS } from "../src/content/characters.js";
import type { Phase } from "../src/game/actions.js";
import { Table } from "../src/game/table.js";
import { observe } from "../src/game/view.js";
import { Rng } from "../src/rng.js";

describe("战役牌桌", () => {
  it("每一关都能打到一方输光，筹码守恒，不出现被删掉的阶段", () => {
    const banned: Phase[] = ["arena", "operate", "draft", "vote", "bid", "marketPick", "marketRemove"];
    for (const s of STAGES) {
      for (let seed = 1; seed <= 20; seed++) {
        const t = new Table(stageTable(newProgress(), s.no, seed));
        const seen = new Set<Phase>();
        const agents = [new RandomAgent(seed), new RandomAgent(seed + 1000)] as const;
        for (let step = 0; t.phase !== "over"; step++) {
          if (step > 5000) throw new Error("卡住了");
          seen.add(t.phase);
          for (const seat of t.toAct()) if (t.toAct().includes(seat)) t.apply(seat, agents[seat].act(t, seat));
        }
        for (const p of banned) expect(seen.has(p), `第 ${s.no} 关出现了 ${p}`).toBe(false);
        if (!s.betting) expect(seen.has("bet")).toBe(false);
        expect(t.stacks[0] + t.stacks[1]).toBe(s.buyIn * 2);
        expect(t.winner).not.toBeNull();
      }
    }
  });

  it("启发式对手在战役牌桌上也能打完", () => {
    for (const no of [1, 7]) {
      const t = new Table(stageTable(newProgress(), no, 5));
      playTable(t, [new HeuristicAgent("cautious", 1, 4), new HeuristicAgent("bluff", 2, 4)]);
      expect(t.phase).toBe("over");
    }
  });

  it("专属规则开局就公开、整张牌桌不变；主场固定，前几关不生效", () => {
    const t = new Table(stageTable(newProgress(), 1, 3));
    expect(t.phase).toBe("place");
    expect(observe(t, 1).ruleId).toBe("V12");
    expect(t.hand.arenaId).toBe("A14");
    expect(t.battleArena()).toBe("NONE");
    expect(observe(t, 0).arenaActive).toBe(false);
    playTable(t, [new RandomAgent(1), new RandomAgent(2)]);
    const rules = t.log.filter((e) => e.type === "reveal").map((e) => (e.type === "reveal" ? e.ruleId : ""));
    expect(new Set(rules)).toEqual(new Set(["V12"]));

    const six = new Table(stageTable(newProgress(), 6, 3));
    expect(six.battleArena()).toBe("A07");
  });

  it("第 7 关每手从前面的规则里随机翻一条", () => {
    const rules = new Set<string>();
    for (let seed = 1; seed <= 30; seed++) rules.add(new Table(stageTable(newProgress(), 7, seed)).hand.ruleId);
    expect(rules.size).toBeGreaterThan(2);
    for (const r of rules) expect(stage(7).rules).toContain(r);
  });

  it("序章各发 3 张全部上场，不下注，布完阵直接开打", () => {
    const t = new Table(stageTable(newProgress(), 0, 9));
    expect(t.hand.dealt[0]).toHaveLength(3);
    const first = t.toAct()[0];
    t.apply(first, { type: "place", picks: [2, 0, 1], eat: null, reveal: 0 });
    t.apply(1 - first as 0 | 1, { type: "place", picks: [0, 1, 2], eat: null, reveal: 0 });
    expect(t.log.some((e) => e.type === "battle")).toBe(true);
    expect(t.log.some((e) => e.type === "betAction")).toBe(false);
  });

  it("牌池来自战役进度和她的固定牌池", () => {
    const p = newProgress();
    const t = new Table(stageTable(p, 3, 1));
    expect(t.pools[0]).toEqual(p.pool);
    expect(t.pools[1]).toEqual(stage(3).foePool);
  });

  it("关卡数据里的编号都存在", () => {
    const ids = new Set(CHARACTERS.map((c) => c.id));
    for (const s of STAGES) {
      for (const id of [...s.foePool, ...s.signature]) expect(ids.has(id), `${s.foe}：${id}`).toBe(true);
      expect(s.taunts.every((tier) => tier.length === 2)).toBe(true);
      expect(() => new Table(stageTable(newProgress(), s.no, 1))).not.toThrow();
    }
    expect(STARTING_POOL.every((id) => ids.has(id))).toBe(true);
  });
});

describe("战役进度", () => {
  it("按顺序解锁；第一次通关才推进、拿魔神牌、挑人", () => {
    const p = newProgress();
    expect(unlocked(p, 0)).toBe(true);
    expect(unlocked(p, 1)).toBe(false);
    expect(recordWin(p, 0, 1)).toEqual([]); // 序章没有挑人
    expect(p.cleared).toBe(1);
    const offer = recordWin(p, 1, 1);
    expect(offer).toHaveLength(3);
    expect(new Set(offer).size).toBe(3);
    for (const id of offer) expect(p.pool).not.toContain(id);
    expect(p.demons).toEqual(["晨星"]);
    expect(p.cleared).toBe(2);
    // 重打已经通关的关：不推进、不给奖励
    expect(recordWin(p, 1, 2)).toEqual([]);
    expect(p.cleared).toBe(2);
    expect(p.demons).toEqual(["晨星"]);
  });

  it("候选优先她那一罪的招牌人物", () => {
    const p = newProgress();
    const offer = rewardOffer(p, 4, 42);
    expect(offer.filter((id) => stage(4).signature.includes(id)).length).toBe(3);
  });

  it("候选只出下一关能用的人物", () => {
    for (let no = 1; no < STAGES.length; no++) {
      const roster = campaignRoster(Math.min(no + 1, STAGES.length - 1));
      for (let seed = 0; seed < 20; seed++) {
        const offer = rewardOffer(newProgress(), no, seed);
        expect(offer).toHaveLength(3);
        for (const id of offer) expect(roster).toContain(id);
        expect(offer).not.toContain("EN3");
      }
    }
    // 路西法的招牌里 PR2 带屏障，第 5 层才教
    expect(rewardOffer(newProgress(), 1, 1)).not.toContain("PR2");
  });

  it("挑人后可以移除一名，但牌池不能低于下限", () => {
    const p = newProgress();
    applyReward(p, "PR1", "WR2");
    expect(p.pool).toContain("PR1");
    expect(p.pool).not.toContain("WR2");
    expect(() => applyReward(p, "PR1", null)).toThrow();
    p.pool = p.pool.slice(0, MIN_CAMPAIGN_POOL - 1);
    expect(() => applyReward(p, "PR2", p.pool[0])).toThrow();
  });

  it("重来次数越多，嘲讽越狠", () => {
    expect([1, 2, 3, 4, 6, 7, 20].map(tauntTier)).toEqual([0, 1, 1, 2, 2, 3, 3]);
    const p = newProgress();
    const rng = new Rng(1);
    for (let i = 1; i <= 8; i++) {
      const line = recordLoss(p, 3, rng);
      expect(stage(3).taunts[tauntTier(i)]).toContain(line);
    }
    expect(p.retries[3]).toBe(8);
    recordWin(p, 0, 1); recordWin(p, 1, 1); recordWin(p, 2, 1); recordWin(p, 3, 1);
    expect(p.clearedAfter[3]).toBe(8);
  });
});
