import type { CharacterDef } from "../types.js";

/**
 * 21 名人物。面板形状各走极端，效果越强面板越弱。
 * 能力的具体结算写在 battle/engine.ts（战斗层）和 game/table.ts（下注、信息层）。
 */
export const CHARACTERS: readonly CharacterDef[] = [
  // 愤怒
  { id: "WR1", name: "小红帽", sin: "愤怒", atk: 2, hp: 7, shape: "multi", armor: 0, barrier: 0,
    ability: "开战时：对手本手每下注或加注一次，攻 +2", tag: "反加注", stage: 1 },
  { id: "WR2", name: "狂战士", sin: "愤怒", atk: 1, hp: 10, shape: "heavy", armor: 0, barrier: 0,
    ability: "战斗中每被打中一段（反击也算），攻 +1", tag: "越打越痛", stage: 1 },
  { id: "WR3", name: "清算者", sin: "愤怒", atk: 5, hp: 4, shape: "heavy", armor: 0, barrier: 0,
    ability: "若对手本手下注或加注过，第 1 轮出手伤害翻倍", tag: "首轮爆发", stage: 2 },
  // 贪婪
  { id: "GR1", name: "豪商", sin: "贪婪", atk: 1, hp: 5, shape: "heavy", armor: 0, barrier: 0,
    ability: "开战时：你本手每投入 10 筹码（含底注、操作费），+1/+1，最多 +4/+4", tag: "花钱养成", stage: 2 },
  { id: "GR2", name: "赎罪券商", sin: "贪婪", atk: 3, hp: 8, shape: "heavy", armor: 0, barrier: 0,
    ability: "开战时：你本手每付一次操作费，屏障 +1（最多 +2）", tag: "花钱买护盾", stage: 1 },
  { id: "GR3", name: "收藏家", sin: "贪婪", atk: 4, hp: 7, shape: "heavy", armor: 0, barrier: 0,
    ability: "击倒敌人后（反击击倒也算），攻 +2，并获得它装备上的攻、血加成", tag: "收割者", stage: 1 },
  // 暴食
  { id: "GL1", name: "放血师", sin: "暴食", atk: 3, hp: 8, shape: "multi", armor: 0, barrier: 0,
    ability: "吸血：自己出手每打中一段，回 1 血（反击不回）", tag: "吸血续航", stage: 1 },
  { id: "GL2", name: "饕餮", sin: "暴食", atk: 3, hp: 8, shape: "heavy", armor: 0, barrier: 0,
    ability: "布阵时可吞掉一名队友，获得它卡面的攻和血，该位置留空", tag: "三合一", stage: 2 },
  { id: "GL3", name: "食腐鸦", sin: "暴食", atk: 2, hp: 7, shape: "heavy", armor: 0, barrier: 0,
    ability: "战斗中每有一名人物倒下（不论敌我），+1/+3", tag: "血战养成", stage: 1 },
  // 嫉妒
  { id: "EN1", name: "密探", sin: "嫉妒", atk: 3, hp: 8, shape: "multi", armor: 0, barrier: 0,
    ability: "亮牌后：偷看对手一张暗牌，然后可交换自己两张暗牌的位置（对手不知道）", tag: "情报", stage: 1 },
  { id: "EN2", name: "镜中人", sin: "嫉妒", atk: 1, hp: 10, shape: "heavy", armor: 0, barrier: 0,
    ability: "开战时：改用对位敌人的攻击形状；攻若低于它，改为它的攻", tag: "镜子", stage: 2 },
  { id: "EN3", name: "扒手", sin: "嫉妒", atk: 3, hp: 7, shape: "heavy", armor: 0, barrier: 0,
    ability: "开战时：拿走对位敌人的装备", tag: "抢装备", stage: 1 },
  // 怠惰
  { id: "SL1", name: "冬眠熊", sin: "怠惰", atk: 1, hp: 9, shape: "heavy", armor: 1, barrier: 0,
    ability: "开战时：你本手每过牌一次，血 +4", tag: "慢打肉盾", stage: 1 },
  { id: "SL2", name: "沉眠巨像", sin: "怠惰", atk: 3, hp: 7, shape: "heavy", armor: 1, barrier: 0,
    ability: "第 1 轮不出手也不反击；开战时：你本手每过牌一次，攻 +2", tag: "慢热巨像", stage: 2 },
  { id: "SL3", name: "隐修士", sin: "怠惰", atk: 2, hp: 8, shape: "heavy", armor: 0, barrier: 0,
    ability: "开战时：若你本手没付过操作费，全队血 +5", tag: "不操作的奖励", stage: 1 },
  // 傲慢
  { id: "PR1", name: "孔雀", sin: "傲慢", atk: 2, hp: 7, shape: "heavy", armor: 0, barrier: 0,
    ability: "被亮出：开战时 +3/+4", tag: "爱被看见", stage: 1 },
  { id: "PR2", name: "无瑕刺客", sin: "傲慢", atk: 3, hp: 3, shape: "heavy", armor: 0, barrier: 1,
    ability: "满血时，出手伤害翻倍", tag: "满血就疼", stage: 2 },
  { id: "PR3", name: "僭王", sin: "傲慢", atk: 3, hp: 7, shape: "heavy", armor: 1, barrier: 0,
    ability: "被亮出：对手在第 1 轮下注中不能弃牌", tag: "逼对手摊牌", stage: 2 },
  // 色欲
  { id: "LU1", name: "痴情骑士", sin: "色欲", atk: 3, hp: 12, shape: "heavy", armor: 0, barrier: 0,
    ability: "守护：敌人攻击它相邻的队友时，改为攻击它", tag: "保镖", stage: 1 },
  { id: "LU2", name: "牵线人", sin: "色欲", atk: 2, hp: 7, shape: "heavy", armor: 0, barrier: 0,
    ability: "开战时：与对位敌人缔结，两者本场都不出手、不反击（仍会被攻击）", tag: "一换一", stage: 2 },
  { id: "LU3", name: "塞壬", sin: "色欲", atk: 3, hp: 5, shape: "heavy", armor: 0, barrier: 0,
    ability: "开战时：魅惑对位敌人，它第 1 轮改打自己身边血最少的队友（身边没人则照常）", tag: "让敌人内讧", stage: 2 },

  // 第二批：每罪补一两名，能力都和原有 21 人不重复（破盾、筹码领先、腐蚀护甲、终局收割、看穿亮牌、后期发力、削弱攻击者、布阵站位）
  { id: "WR4", name: "攻城锤手", sin: "愤怒", atk: 4, hp: 6, shape: "heavy", armor: 0, barrier: 0,
    ability: "第一次打掉敌人一层屏障后，攻 +2", tag: "破盾", stage: 1 },
  { id: "GR4", name: "金库守卫", sin: "贪婪", atk: 2, hp: 9, shape: "heavy", armor: 1, barrier: 0,
    ability: "开战时：若你剩余筹码多于对手，屏障 +1", tag: "守财", stage: 1 },
  { id: "GL4", name: "噬铁软泥", sin: "暴食", atk: 3, hp: 8, shape: "multi", armor: 0, barrier: 0,
    ability: "打中带护甲的敌人时，它护甲 -1（每个敌人限一次）", tag: "腐蚀", stage: 1 },
  { id: "GL5", name: "大野狼", sin: "暴食", atk: 4, hp: 7, shape: "multi", armor: 0, barrier: 0,
    ability: "敌方只剩一人时，出手伤害 +4", tag: "收割", stage: 2 },
  { id: "EN4", name: "影子", sin: "嫉妒", atk: 4, hp: 7, shape: "heavy", armor: 0, barrier: 0,
    ability: "攻击被亮出的敌人时，出手伤害 +2", tag: "看穿亮牌", stage: 1 },
  { id: "SL4", name: "守夜人", sin: "怠惰", atk: 4, hp: 8, shape: "heavy", armor: 0, barrier: 0,
    ability: "从第 3 轮起，出手伤害 +3", tag: "后期发力", stage: 2 },
  { id: "LU4", name: "交际花", sin: "色欲", atk: 3, hp: 6, shape: "heavy", armor: 0, barrier: 1,
    ability: "逢场作戏：打中它的敌人，下一次攻击 -2（每个敌人一次）", tag: "削弱", stage: 2 },
  { id: "LU5", name: "双子", sin: "色欲", atk: 3, hp: 9, shape: "multi", armor: 0, barrier: 0,
    ability: "开战时：若站在 2 号位且两侧都有队友，全队血 +2", tag: "布阵", stage: 2 },
];

const BY_ID = new Map(CHARACTERS.map((c) => [c.id, c]));

export function character(id: string): CharacterDef {
  const c = BY_ID.get(id);
  if (!c) throw new Error(`未知人物：${id}`);
  return c;
}

export const CHARACTER_IDS: readonly string[] = CHARACTERS.map((c) => c.id);
