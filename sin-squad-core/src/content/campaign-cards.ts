import type { CharacterDef } from "../types.js";
import { CHARACTERS, character } from "./characters.js";

/**
 * 战役用的人物卡面（战役 §3.5）。自由牌桌照旧用原版。
 *
 * - 战役没有护甲：护甲 1 换成血 +2（试制参数）。
 * - 战役没有操作费和装备：靠它们触发的能力改写。
 * - 扒手只靠装备，移出战役。
 */
export const ARMOR_TO_HP = 2;

const REWRITES: Record<string, string> = {
  GR2: "开战时：你本手每下注或加注一次，屏障 +1（最多 +2）",
  SL3: "开战时：若你本手没下注或加注过，全队血 +5",
  GL4: "打中带屏障的敌人时，多打掉它一层屏障",
  GR3: "击倒敌人后（反击击倒也算），攻 +2",
  GR1: "开战时：你本手每投入 10 筹码（含底注），+1/+1，最多 +4/+4",
};

/** 不进战役的人物。 */
export const CAMPAIGN_EXCLUDED: readonly string[] = ["EN3"];

/**
 * 人物从第几关起才会出现在任何一方的牌池里（0 = 序章）。
 * 按“能力要用到的机制是哪一关教的”来定：
 * 1 亮牌与下注，2 偷看，4 下注强化，5 屏障，6 吞噬。
 */
export const UNLOCK_LEVEL: Readonly<Record<string, number>> = {
  // 起始牌池：不依赖下注、不带屏障
  WR2: 0, GR3: 0, GL1: 0, GL3: 0, LU1: 0, SL4: 0, GL5: 0, LU5: 0,
  // 只看战斗、或看“被亮出”
  PR1: 1, PR3: 1, EN4: 1, EN2: 1, LU2: 1, LU3: 1,
  EN1: 2,
  // 看本手的下注行为
  WR1: 4, WR3: 4, GR1: 4, SL1: 4, SL2: 4, SL3: 4,
  // 带屏障、或和屏障有关
  PR2: 5, LU4: 5, GR2: 5, GR4: 5, WR4: 5, GL4: 5,
  GL2: 6,
};

const CACHE = new Map<string, CharacterDef>();

/** 战役版卡面：护甲换成血，改写的能力换上新文字。 */
export function campaignCard(id: string): CharacterDef {
  const hit = CACHE.get(id);
  if (hit) return hit;
  const c = character(id);
  const card: CharacterDef = {
    ...c,
    hp: c.hp + ARMOR_TO_HP * c.armor,
    armor: 0,
    ability: REWRITES[id] ?? c.ability,
  };
  CACHE.set(id, card);
  return card;
}

/** 第 level 关里能出现的人物（0 = 序章）。 */
export function campaignRoster(level: number): string[] {
  return CHARACTERS
    .filter((c) => !CAMPAIGN_EXCLUDED.includes(c.id) && (UNLOCK_LEVEL[c.id] ?? Infinity) <= level)
    .map((c) => c.id);
}
