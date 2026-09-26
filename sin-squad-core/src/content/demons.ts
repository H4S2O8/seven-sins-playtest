import type { CharacterDef } from "../types.js";

/**
 * 魔神牌（战役 §3.7）：每位姐妹一张，完全公开，不进牌池。
 * 从第 2 轮起，本方一有空位就降临到编号最小的空位上（每场一次）。
 *
 * 攻血和能力按《01-魔神牌.md》v1.1（试制参数），结算写在 battle/engine.ts。
 */
export const DEMONS: readonly CharacterDef[] = [
  { id: "DM1", name: "晨星", sin: "傲慢", atk: 5, hp: 10, shape: "heavy", armor: 0, barrier: 0,
    ability: "决斗：降临时，向敌方攻最高的人下战书。此后她只打它，它也只打她，直到一方倒下", tag: "路西法", stage: 3 },
  { id: "DM2", name: "深渊之眼", sin: "嫉妒", atk: 2, hp: 12, shape: "heavy", armor: 0, barrier: 0,
    ability: "夺攻：降临时，从每名敌人身上各抢走 1 点攻（最低留 1）", tag: "利维坦", stage: 3 },
  { id: "DM3", name: "焚怒", sin: "愤怒", atk: 3, hp: 14, shape: "heavy", armor: 0, barrier: 0,
    ability: "横扫：她出手和反击都打到所有敌人", tag: "撒旦", stage: 3 },
  { id: "DM4", name: "永眠", sin: "怠惰", atk: 3, hp: 14, shape: "heavy", armor: 0, barrier: 0,
    ability: "只反击：她从不出手；反击时打出双倍的攻", tag: "贝尔芬格", stage: 3 },
  { id: "DM5", name: "金山", sin: "贪婪", atk: 4, hp: 12, shape: "heavy", armor: 0, barrier: 0,
    ability: "利息：降临时，以及她每次打中敌人或被敌人打中时，你从对手那里收 5 筹码（每手最多 20，输了也收）", tag: "玛门", stage: 3 },
  { id: "DM6", name: "万蝇之王", sin: "暴食", atk: 4, hp: 8, shape: "heavy", armor: 0, barrier: 0,
    ability: "饿坏了：降临后马上出手一次；她出手击倒敌人后，再出手一次", tag: "别西卜", stage: 3 },
  { id: "DM7", name: "欲之王", sin: "色欲", atk: 5, hp: 3, shape: "heavy", armor: 0, barrier: 0,
    ability: "换心：降临时，和敌方血最多的人交换当前血量", tag: "阿斯莫德", stage: 3 },
];

export const DEMON_IDS: readonly string[] = DEMONS.map((d) => d.id);

/** 按名字查魔神牌编号（战役进度和关卡表里记的是名字）。 */
export function demonId(name: string): string {
  const d = DEMONS.find((x) => x.name === name);
  if (!d) throw new Error(`未知魔神牌：${name}`);
  return d.id;
}
