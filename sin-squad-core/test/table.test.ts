import { describe, expect, it } from "vitest";
import { HeuristicAgent, playTable, RandomAgent } from "../src/ai/agents.js";
import type { Action, Phase } from "../src/game/actions.js";
import { Table } from "../src/game/table.js";
import { legalActions, observe } from "../src/game/view.js";
import type { Seat } from "../src/types.js";

/** 被动策略：能过牌就过牌、要跟就跟，其余取第一个合法动作。 */
function passive(t: Table, seat: Seat): Action {
  const acts = legalActions(t, seat);
  const find = (type: Action["type"]) => acts.find((a) => a.type === type);
  switch (t.phase) {
    case "bet": return find("check") ?? find("call")!;
    case "operate": return { type: "operate", draft: false };
    case "vote": return { type: "vote", activate: true };
    case "marketRemove": return { type: "marketRemove", poolIndex: null };
    default: return acts[0];
  }
}

function driveUntil(t: Table, phase: Phase, policy = passive) {
  for (let i = 0; i < 500 && t.phase !== phase; i++) {
    for (const s of t.toAct()) if (t.toAct().includes(s)) t.apply(s, policy(t, s));
  }
  expect(t.phase).toBe(phase);
}

describe("整张牌桌", () => {
  it("随机对手打几百张牌桌：不卡死、筹码守恒、最后有人赢", () => {
    for (let seed = 1; seed <= 300; seed++) {
      const t = new Table({ seed });
      playTable(t, [new RandomAgent(seed), new RandomAgent(seed + 1000)]);
      expect(t.phase).toBe("over");
      expect(t.stacks[0] + t.stacks[1]).toBe(200);
      expect(t.winner).not.toBeNull();
    }
  });

  it("启发式对手也能正常打完", () => {
    for (let seed = 1; seed <= 5; seed++) {
      const t = new Table({ seed });
      playTable(t, [new HeuristicAgent("cautious", seed), new HeuristicAgent("bluff", seed + 1)]);
      expect(t.phase).toBe("over");
    }
  });

  it("同一个种子、同样的动作，得到完全相同的牌桌", () => {
    const run = () => {
      const t = new Table({ seed: 77 });
      playTable(t, [new RandomAgent(1), new RandomAgent(2)]);
      return JSON.stringify(t.log);
    };
    expect(run()).toBe(run());
  });
});

describe("下注与操作费", () => {
  it("操作费按有效筹码封顶", () => {
    const t = new Table({ seed: 3 });
    t.stacks = [140, 50]; // 底注后奖池 10，总额仍为 200
    driveUntil(t, "bet");
    const first = t.toAct()[0];
    t.apply(first, { type: "bet", amount: 30 });
    t.apply(t.toAct()[0], { type: "call" });
    expect(t.phase).toBe("operate");
    expect(t.hand.opFee).toBe(20); // 短码跟注后只剩 20
  });

  it("全押时退回本轮对方跟不上的部分", () => {
    const t = new Table({ seed: 4 });
    t.stacks = [140, 50];
    driveUntil(t, "bet");
    const first = t.toAct()[0];
    if (first === 0) {
      t.apply(0, { type: "bet", amount: 100 });
      t.apply(1, { type: "allIn" });
    } else {
      t.apply(1, { type: "allIn" });
      t.apply(0, { type: "call" });
    }
    expect(t.hand.allIn).toBe(true);
    expect(t.hand.invested[0]).toBe(t.hand.invested[1]);
    t.checkInvariant();
  });

  it("弃牌：奖池归对方，不打战斗", () => {
    const t = new Table({ seed: 5 });
    driveUntil(t, "bet");
    const folder = t.toAct()[0];
    expect(t.canFold(folder)).toBe(true);
    t.apply(folder, { type: "fold" });
    expect(t.hand.outcome?.by).toBe("fold");
    expect(t.hand.battle).toBeNull();
    expect(t.stacks[folder]).toBe(95);
    expect(t.phase).toBe("marketPick");
    expect(t.toAct()).toEqual([folder]); // 输家先挑
  });

  it("冠冕者被亮出时，对手第 1 轮不能弃牌", () => {
    for (let seed = 1; seed < 400; seed++) {
      const t = new Table({ seed });
      driveUntil(t, "place");
      const placer = t.toAct()[0];
      const crownIdx = t.hand.dealt[placer].indexOf("PR3");
      if (crownIdx < 0) continue;
      const rest = [0, 1, 2, 3].filter((i) => i !== crownIdx).slice(0, 2);
      t.apply(placer, { type: "place", picks: [crownIdx, rest[0], rest[1]], eat: null, reveal: 0 });
      driveUntil(t, "bet");
      const foe: Seat = placer === 0 ? 1 : 0;
      expect(t.canFold(foe)).toBe(false);
      expect(legalActions(t, foe).some((a) => a.type === "fold")).toBe(false);
      return;
    }
    throw new Error("没有找到发到冠冕者的种子");
  });
});

describe("窥视者", () => {
  /** 找一个非庄家发到窥视者的牌桌，把它暗置排上，双方排完位后进入窥视阶段。 */
  function toPeek() {
    for (let seed = 1; seed < 500; seed++) {
      const t = new Table({ seed });
      driveUntil(t, "place");
      const placer = t.toAct()[0];
      const idx = t.hand.dealt[placer].indexOf("EN1");
      if (idx < 0) continue;
      const rest = [0, 1, 2, 3].filter((i) => i !== idx).slice(0, 2);
      t.apply(placer, { type: "place", picks: [rest[0], idx, rest[1]], eat: null, reveal: 0 }); // 窥视者暗置在 2 号位
      const dealer: Seat = placer === 0 ? 1 : 0;
      if (t.hand.dealt[dealer].includes("EN1")) continue; // 只要一方有窥视者
      t.apply(dealer, { type: "place", picks: [0, 1, 2], eat: null, reveal: 0 });
      expect(t.phase).toBe("peek");
      expect(t.toAct()).toEqual([placer]);
      return { t, seat: placer };
    }
    throw new Error("没有找到合适的种子");
  }

  it("偷看是暗中进行的：不写进公开的牌桌记录", () => {
    const { t, seat } = toPeek();
    const before = t.log.length;
    t.apply(seat, { type: "peek", pos: 1 });
    expect(t.log.length).toBe(before);
    expect(observe(t, seat).me.peek?.pos).toBe(1);
    expect(observe(t, seat === 0 ? 1 : 0).me.peek).toBeNull();
  });

  it("偷看后可以交换自己两名暗置人物；亮出的那名不能动", () => {
    const { t, seat } = toPeek();
    t.apply(seat, { type: "peek", pos: 2 });
    const slots = t.hand.placement[seat]!.slots.slice();
    expect(() => t.apply(seat, { type: "peekSwap", swap: [0, 1] })).toThrow(); // 0 号位是亮出的
    expect(legalActions(t, seat)).toContainEqual({ type: "peekSwap", swap: [1, 2] });
    t.apply(seat, { type: "peekSwap", swap: [1, 2] });
    expect(t.hand.placement[seat]!.slots).toEqual([slots[0], slots[2], slots[1]]);
    expect(t.phase).toBe("bet");
  });
});

describe("公共效果暗标", () => {
  function toBid(seed: number) {
    const t = new Table({ seed });
    driveUntil(t, "vote");
    t.apply(0, { type: "vote", activate: true });
    t.apply(1, { type: "vote", activate: false });
    expect(t.phase).toBe("bid");
    return t;
  }

  it("出价高的一方决定去留，只付自己的出价", () => {
    const t = toBid(6);
    const before = [t.stacks[0], t.stacks[1]];
    t.apply(0, { type: "bid", amount: 15 });
    t.apply(1, { type: "bid", amount: 10 });
    expect(t.hand.peActive).toBe(true);
    expect(t.stacks[0]).toBe(before[0] - 15);
    expect(t.stacks[1]).toBe(before[1]);
    expect(t.phase).toBe("bet");
  });

  it("出价相同：不生效，谁都不付钱", () => {
    const t = toBid(6);
    const before = [t.stacks[0], t.stacks[1]];
    t.apply(0, { type: "bid", amount: 10 });
    t.apply(1, { type: "bid", amount: 10 });
    expect(t.hand.peActive).toBe(false);
    expect([t.stacks[0], t.stacks[1]]).toEqual(before);
  });

  it("出价不能超过有效筹码", () => {
    const t = toBid(6);
    expect(() => t.apply(0, { type: "bid", amount: t.hand.bidCap + 1 })).toThrow();
  });
});

describe("隐藏信息", () => {
  it("规则和公共效果翻开前看不到；对手的暗置人物不在观察里", () => {
    const t = new Table({ seed: 8 });
    driveUntil(t, "bet");
    for (const s of [0, 1] as Seat[]) {
      const obs = observe(t, s);
      expect(obs.ruleId).toBeNull();
      expect(obs.publicEffectId).toBeNull();
      const foe = t.hand.placement[s === 0 ? 1 : 0]!;
      expect(obs.opponent.revealed?.characterId).toBe(foe.slots[foe.reveal]);
      expect("placement" in obs.opponent).toBe(false);
      expect("dealt" in obs.opponent).toBe(false);
    }
  });

  it("表决和出价在双方都提交前不公开", () => {
    const t = new Table({ seed: 6 });
    driveUntil(t, "vote");
    t.apply(0, { type: "vote", activate: true });
    const obs = observe(t, 1);
    expect(obs.opponent.submitted).toBe(true);
    expect(JSON.stringify(obs)).not.toContain('"vote":true');
  });
});

describe("牌桌层", () => {
  it("筹码少的一方选场地", () => {
    const t = new Table({ seed: 9 });
    driveUntil(t, "bet");
    const folder = t.toAct()[0];
    expect(t.canFold(folder)).toBe(true);
    t.apply(folder, { type: "fold" });
    driveUntil(t, "arena");
    expect(t.hand.arenaChooser).toBe(folder);
  });

  it("每 5 手底注翻倍；市场按阶段升级", () => {
    expect(Table.marketStageFor(5)).toBe(1);
    expect(Table.marketStageFor(6)).toBe(2);
    expect(Table.marketStageFor(11)).toBe(3);
  });

  it("移除后牌池不能少于下限", () => {
    const t = new Table({ seed: 10, initialPoolSize: 6, minPoolSize: 7 });
    driveUntil(t, "marketRemove", (tt, s) => (tt.phase === "bet" && tt.canFold(s) ? { type: "fold" } : passive(tt, s)));
    const seat = t.toAct()[0];
    expect(t.pools[seat].length).toBe(7);
    expect(() => t.apply(seat, { type: "marketRemove", poolIndex: 0 })).toThrow();
    expect(legalActions(t, seat)).toEqual([{ type: "marketRemove", poolIndex: null }]);
  });
});
