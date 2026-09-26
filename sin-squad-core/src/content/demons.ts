import type { CharacterDef } from "../types.js";

/**
 * 魔神牌（战役 §3.7）：每位姐妹一张，完全公开，不进牌池。
 * 从第 2 轮起，每轮开始时本方有空位，就降临到编号最小的空位上（每场一次）。
 *
 * 数值是试制参数。能力还在另一个帖子里重新设计，定稿前魔神只按攻、血上场，能力不结算。
 */
export const DEMONS: readonly CharacterDef[] = [
  { id: "DM1", name: "晨星", sin: "傲慢", atk: 4, hp: 12, shape: "heavy", armor: 0, barrier: 0,
    ability: "（能力待定）", tag: "路西法", stage: 3 },
  { id: "DM2", name: "深渊之眼", sin: "嫉妒", atk: 2, hp: 12, shape: "heavy", armor: 0, barrier: 0,
    ability: "（能力待定）", tag: "利维坦", stage: 3 },
  { id: "DM3", name: "焚怒", sin: "愤怒", atk: 3, hp: 12, shape: "heavy", armor: 0, barrier: 0,
    ability: "（能力待定）", tag: "撒旦", stage: 3 },
  { id: "DM4", name: "永眠", sin: "怠惰", atk: 2, hp: 10, shape: "heavy", armor: 0, barrier: 0,
    ability: "（能力待定）", tag: "贝尔芬格", stage: 3 },
  { id: "DM5", name: "金山", sin: "贪婪", atk: 3, hp: 10, shape: "heavy", armor: 0, barrier: 0,
    ability: "（能力待定）", tag: "玛门", stage: 3 },
  { id: "DM6", name: "万蝇之王", sin: "暴食", atk: 3, hp: 10, shape: "heavy", armor: 0, barrier: 0,
    ability: "（能力待定）", tag: "别西卜", stage: 3 },
  { id: "DM7", name: "欲之王", sin: "色欲", atk: 3, hp: 12, shape: "heavy", armor: 0, barrier: 0,
    ability: "（能力待定）", tag: "阿斯莫德", stage: 3 },
];

export const DEMON_IDS: readonly string[] = DEMONS.map((d) => d.id);
