import type { EatChoice } from "../types.js";

/** 玩家能提交的所有动作。 */
export type Action =
  /** 落后方从两张场地里选一张。 */
  | { type: "chooseArena"; index: 0 | 1 }
  /** 传统牌桌布阵：picks[i] 是放在 i 号位的候选牌序号。 */
  | { type: "place"; picks: [number, number, number]; eat: EatChoice | null; reveal: number }
  | { type: "rerollPlace"; pos: 0 | 1 | 2 }
  /** 密探：暗中查看对手一个暗置位置。 */
  | { type: "peek"; pos: number }
  /** 密探偷看之后：交换自己两名暗置人物的位置（null = 不交换）。对手不会知道。 */
  | { type: "peekSwap"; swap: [number, number] | null }
  /** 第二次翻开：暗选自己再翻开哪一名（双方选完一起翻开）。 */
  | { type: "reveal2"; pos: number }
  | { type: "check" }
  | { type: "bet"; amount: number }
  | { type: "call" }
  /** 加注到本轮总额 to。 */
  | { type: "raise"; to: number }
  | { type: "allIn" }
  | { type: "fold" }
  /** 下注匹配后的唯一一次操作：跳过、拿装备，或公开重设三人的优先目标。 */
  | { type: "operate"; operation: "pass" | "draft" }
  | { type: "operate"; operation: "retarget"; targets: [number, number, number] }
  /** 从三张候选装备里选一张，装到 pos 号位。 */
  | { type: "draft"; offerIndex: number; pos: number }
  /** 公共效果：投生效 / 不生效。 */
  | { type: "vote"; activate: boolean }
  /** 公共效果暗标出价。 */
  | { type: "bid"; amount: number }
  /** 结算后从市场挑一名人物进牌池。 */
  | { type: "marketPick"; index: number }
  /** 从自己牌池移除一名（null 表示不移除）。 */
  | { type: "marketRemove"; poolIndex: number | null };

export type Phase =
  | "arena"
  | "place"
  | "peek"
  | "reveal2"
  | "bet"
  | "operate"
  | "draft"
  | "vote"
  | "bid"
  | "marketPick"
  | "marketRemove"
  | "over";
