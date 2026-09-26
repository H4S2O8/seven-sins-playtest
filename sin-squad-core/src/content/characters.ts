import type { CharacterDef } from "../types.js";

/**
 * 21 名人物。面板形状各走极端，效果越强面板越弱。
 * 能力的具体结算写在 battle/engine.ts（战斗层）和 game/table.ts（下注、信息层）。
 */
export const CHARACTERS: readonly CharacterDef[] = [
  // 愤怒
  { id: "WR1", name: "叫阵骑士", sin: "愤怒", atk: 2, hp: 7, shape: "multi", armor: 0, barrier: 0,
    ability: "对手本手每下注或加注一次，攻 +2", tag: "反加注", stage: 1 },
  { id: "WR2", name: "狂战士", sin: "愤怒", atk: 1, hp: 10, shape: "heavy", armor: 0, barrier: 0,
    ability: "战斗中每受到一段伤害，攻 +1", tag: "越打越痛", stage: 1 },
  { id: "WR3", name: "清算者", sin: "愤怒", atk: 5, hp: 4, shape: "heavy", armor: 0, barrier: 0,
    ability: "若对手本手加注过，第一轮攻击翻倍", tag: "首轮爆发", stage: 2 },
  // 贪婪
  { id: "GR1", name: "豪商", sin: "贪婪", atk: 1, hp: 5, shape: "heavy", armor: 0, barrier: 0,
    ability: "你本手每投入 10 筹码，+1/+1（最多 +4/+4）", tag: "花钱养成", stage: 2 },
  { id: "GR2", name: "赎罪券商", sin: "贪婪", atk: 3, hp: 8, shape: "heavy", armor: 0, barrier: 0,
    ability: "你本手每付一次操作费，开战时得一层屏障（最多 2）", tag: "花钱买护盾", stage: 1 },
  { id: "GR3", name: "收藏家", sin: "贪婪", atk: 4, hp: 7, shape: "heavy", armor: 0, barrier: 0,
    ability: "击倒敌人后，攻 +2 并拿走对方的装备加成", tag: "收割者", stage: 1 },
  // 暴食
  { id: "GL1", name: "血蛭", sin: "暴食", atk: 3, hp: 8, shape: "multi", armor: 0, barrier: 0,
    ability: "吸血：自己攻击每打中一段，回复 1 血（反击不算）", tag: "吸血续航", stage: 1 },
  { id: "GL2", name: "饕餮", sin: "暴食", atk: 3, hp: 8, shape: "heavy", armor: 0, barrier: 0,
    ability: "布阵时可以吞掉一名队友，获得它的攻和血（该位置空出）", tag: "三合一", stage: 2 },
  { id: "GL3", name: "食腐鸦", sin: "暴食", atk: 2, hp: 7, shape: "heavy", armor: 0, barrier: 0,
    ability: "每有一名人物倒下（不论敌我），+1/+3", tag: "血战养成", stage: 1 },
  // 嫉妒
  { id: "EN1", name: "密探", sin: "嫉妒", atk: 3, hp: 8, shape: "multi", armor: 0, barrier: 0,
    ability: "亮牌后，暗中查看对手一名暗置人物，然后可以交换自己两名暗置人物的位置（对手不会知道）", tag: "情报", stage: 1 },
  { id: "EN2", name: "镜中人", sin: "嫉妒", atk: 1, hp: 10, shape: "heavy", armor: 0, barrier: 0,
    ability: "开战时，攻和攻击形状变得与对位敌人相同（取较高攻）", tag: "镜子", stage: 2 },
  { id: "EN3", name: "扒手", sin: "嫉妒", atk: 3, hp: 7, shape: "heavy", armor: 0, barrier: 0,
    ability: "开战时，拿走对位敌人的装备", tag: "抢装备", stage: 1 },
  // 怠惰
  { id: "SL1", name: "冬眠熊", sin: "怠惰", atk: 1, hp: 9, shape: "heavy", armor: 1, barrier: 0,
    ability: "你本手每过牌一次，+0/+4", tag: "慢打肉盾", stage: 1 },
  { id: "SL2", name: "沉眠巨像", sin: "怠惰", atk: 3, hp: 7, shape: "heavy", armor: 1, barrier: 0,
    ability: "第一轮不出手；你本手每过牌一次，攻 +2", tag: "慢热巨像", stage: 2 },
  { id: "SL3", name: "隐修士", sin: "怠惰", atk: 2, hp: 8, shape: "heavy", armor: 0, barrier: 0,
    ability: "若你本手没付过操作费，开战时全队 +0/+5", tag: "不操作的奖励", stage: 1 },
  // 傲慢
  { id: "PR1", name: "孔雀", sin: "傲慢", atk: 2, hp: 7, shape: "heavy", armor: 0, barrier: 0,
    ability: "被亮出时 +3/+4", tag: "爱被看见", stage: 1 },
  { id: "PR2", name: "无瑕刺客", sin: "傲慢", atk: 3, hp: 3, shape: "heavy", armor: 0, barrier: 1,
    ability: "满血时攻击翻倍", tag: "满血就疼", stage: 2 },
  { id: "PR3", name: "僭王", sin: "傲慢", atk: 3, hp: 7, shape: "heavy", armor: 1, barrier: 0,
    ability: "被亮出时，对手在第 1 轮下注不能弃牌", tag: "逼对手摊牌", stage: 2 },
  // 色欲
  { id: "LU1", name: "痴情骑士", sin: "色欲", atk: 3, hp: 12, shape: "heavy", armor: 0, barrier: 0,
    ability: "守护：相邻队友受到的攻击改由它承受", tag: "保镖", stage: 1 },
  { id: "LU2", name: "牵线人", sin: "色欲", atk: 2, hp: 7, shape: "heavy", armor: 0, barrier: 0,
    ability: "开战时与对位敌人缔结，两者本场都不出手（仍可被攻击）", tag: "一换一", stage: 2 },
  { id: "LU3", name: "塞壬", sin: "色欲", atk: 3, hp: 5, shape: "heavy", armor: 0, barrier: 0,
    ability: "开战时，对位敌人第一轮改打它自己的相邻队友", tag: "让敌人内讧", stage: 2 },
];

const BY_ID = new Map(CHARACTERS.map((c) => [c.id, c]));

export function character(id: string): CharacterDef {
  const c = BY_ID.get(id);
  if (!c) throw new Error(`未知人物：${id}`);
  return c;
}

export const CHARACTER_IDS: readonly string[] = CHARACTERS.map((c) => c.id);
