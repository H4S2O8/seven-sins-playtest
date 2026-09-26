import { runBattle, type BattleInput, type BattleResult, type CampaignBattleRules } from "../battle/engine.js";
import { campaignRoster } from "../content/campaign-cards.js";
import { DEMON_IDS } from "../content/demons.js";
import { Rng } from "../rng.js";
import type { BetContext, TeamSetup } from "../types.js";

/**
 * 战役的战斗模拟：按关卡的牌池、专属规则、主场和魔神，随机打很多场，
 * 对比“转线”和“打最近的敌人”两种写法、有没有魔神。
 *
 * 关卡表先在这里写一份战斗要用的部分（专属规则、主场、魔神）；
 * 牌桌那边的关卡表合进来之后，改成直接读那一份。
 */
export interface LevelBattleSetup {
  /** 专属胜利规则；第 7 关每手从这里随机一条。 */
  rules: string[];
  /** 有效果的主场；没有则为 null。 */
  arenaId: string | null;
}

export const LEVEL_BATTLE: readonly LevelBattleSetup[] = [
  { rules: ["V01"], arenaId: null }, // 序章 · 看板娘：全灭
  { rules: ["V12"], arenaId: null }, // 1 路西法：众目所向
  { rules: ["V08"], arenaId: null }, // 2 利维坦：掐灭火力
  { rules: ["V03"], arenaId: null }, // 3 撒旦：连续击破
  { rules: ["V07"], arenaId: null }, // 4 贝尔芬格：斩旗
  { rules: ["V09"], arenaId: null }, // 5 玛门：薄弱环节
  { rules: ["V01"], arenaId: "A07" }, // 6 别西卜：吃干净，水淹地牢
  { rules: ["V12", "V08", "V03", "V07", "V09", "V01"], arenaId: "A04" }, // 7 阿斯莫德：七罪之约，许愿井
];

/** 没有效果的主场（只当背景）。 */
const NO_ARENA = "NONE";

function campaignBet(rng: Rng, level: number, revealedPos: number): BetContext {
  if (level === 0) return { invested: 10, betOrRaiseCount: 0, checkCount: 0, opsPaid: 0, revealedPos };
  return {
    invested: rng.pick([10, 20, 30, 50, 70]),
    betOrRaiseCount: rng.pick([0, 0, 1, 1, 2]),
    checkCount: rng.pick([0, 1, 1, 2]),
    opsPaid: 0,
    revealedPos,
    stack: rng.pick([30, 60, 90, 120]),
  };
}

function campaignTeam(rng: Rng, level: number, roster: string[], ids?: string[]): TeamSetup {
  const chars = ids ?? rng.sample(roster, 3);
  const revealedPos = rng.int(3);
  return { slots: chars.map((c) => ({ characterId: c, equipmentId: null })), eat: null, bet: campaignBet(rng, level, revealedPos) };
}

/** 第 level 关双方带的魔神：玩家从打败过的姐妹里挑一张（第 1 关还没有），对手带自己的。 */
function levelDemons(rng: Rng, level: number): [string | null, string | null] {
  if (level === 0) return [null, null];
  const mine = level >= 2 ? rng.pick(DEMON_IDS.slice(0, level - 1)) : null;
  return [mine, DEMON_IDS[level - 1]];
}

export interface Variant {
  name: string;
  rules: CampaignBattleRules;
  demons: boolean;
}

export const VARIANTS: readonly Variant[] = [
  { name: "转线 · 无魔神", rules: { hellfire: true, cards: true }, demons: false },
  { name: "打最近 · 无魔神", rules: { hellfire: true, cards: true, nearest: true }, demons: false },
  { name: "转线 · 魔神", rules: { hellfire: true, cards: true }, demons: true },
  { name: "打最近 · 魔神", rules: { hellfire: true, cards: true, nearest: true }, demons: true },
];

export function levelBattle(rng: Rng, level: number, v: Variant, mine?: string[]): BattleInput {
  const setup = LEVEL_BATTLE[level];
  const roster = campaignRoster(level);
  const a = campaignTeam(rng, level, roster, mine);
  const b = campaignTeam(rng, level, roster);
  const demons = levelDemons(rng, level);
  return {
    teams: [a, b],
    ruleId: rng.pick(setup.rules),
    arenaId: setup.arenaId ?? NO_ARENA,
    publicEffectId: null,
    pot: a.bet.invested + b.bet.invested,
    firstSeat: rng.int(2) as 0 | 1,
    campaign: { ...v.rules, demons: v.demons ? demons : undefined },
  };
}

/** 先击倒一名敌人的一方（同一次攻击里双方都倒人则不算）；没人倒下为 null。 */
export function firstKiller(r: BattleResult): 0 | 1 | null {
  for (const f of r.frames) {
    const dead = new Set(f.events.filter((e) => e.type === "death").map((e) => e.type === "death" && e.seat));
    if (dead.size === 1) return dead.has(0) ? 1 : 0;
    if (dead.size === 2) return null;
  }
  return null;
}

export interface LevelStats {
  battles: number;
  draws: number;
  avgRounds: number;
  /** 业火真正烧到的战斗。 */
  hellfire: number;
  /** 有魔神降临的战斗。 */
  demon: number;
  /** 先击倒一方最终赢下的比例，以及统计到的场数。 */
  firstKillWins: number;
  firstKillCases: number;
  /** 魔神降临的战斗里，先被击倒的一方（先拿到魔神）翻盘的比例。 */
  comeback: number;
  comebackCases: number;
}

export function levelStats(level: number, v: Variant, n: number, seed = 20260926): LevelStats {
  const rng = new Rng(seed + level);
  const s: LevelStats = { battles: n, draws: 0, avgRounds: 0, hellfire: 0, demon: 0, firstKillWins: 0, firstKillCases: 0, comeback: 0, comebackCases: 0 };
  let rounds = 0;
  for (let i = 0; i < n; i++) {
    const r = runBattle(levelBattle(rng, level, v));
    rounds += r.rounds;
    if (r.winner === null) s.draws++;
    if (r.events.some((e) => e.type === "hellfire")) s.hellfire++;
    const demon = r.events.some((e) => e.type === "demon");
    if (demon) s.demon++;
    const fk = firstKiller(r);
    if (fk !== null && r.winner !== null) {
      s.firstKillCases++;
      if (r.winner === fk) s.firstKillWins++;
      if (demon) {
        s.comebackCases++;
        if (r.winner !== fk) s.comeback++;
      }
    }
  }
  s.avgRounds = rounds / n;
  return s;
}

/** 开局胜率分布：固定一方三名人物，对随机对手打 per 场。 */
export function levelOpening(level: number, v: Variant, teams: number, per: number, seed = 7): number[] {
  const rng = new Rng(seed + level);
  const roster = campaignRoster(level);
  const wrs: number[] = [];
  for (let t = 0; t < teams; t++) {
    const mine = rng.sample(roster, 3);
    let score = 0;
    for (let i = 0; i < per; i++) {
      const r = runBattle(levelBattle(rng, level, v, mine));
      score += r.winner === 0 ? 1 : r.winner === null ? 0.5 : 0;
    }
    wrs.push(score / per);
  }
  return wrs.sort((a, b) => a - b);
}
