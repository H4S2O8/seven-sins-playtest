import type { BattleEvent, BattleResult } from "../src/battle/engine.js";
import { character } from "../src/content/characters.js";
import { arena, equipment, publicEffect, rule } from "../src/content/tables.js";
import type { TableEvent } from "../src/game/table.js";
import type { AttackShape, Seat, Sin } from "../src/types.js";

/** 网页里的中文文案：牌桌记录、战斗记录、规则说明。 */

export const HUMAN: Seat = 0;
export const AI: Seat = 1;

export const who = (s: Seat) => (s === HUMAN ? "你" : "对手");
export const posName = (p: number) => `${p + 1}号位`;
export const shapeName = (s: AttackShape) => (s === "heavy" ? "重击" : "连击");
export const num = (x: number) => (Number.isInteger(x) ? String(x) : x.toFixed(1));

export const SIN_COLOR: Record<Sin, string> = {
  愤怒: "#b5523b",
  贪婪: "#c79a3a",
  暴食: "#7f9a3a",
  嫉妒: "#3f8f7a",
  怠惰: "#5b7aa8",
  傲慢: "#8a5aa8",
  色欲: "#b8547e",
};

export const esc = (s: string) =>
  s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!);

const BET_LABEL: Record<string, string> = { check: "过牌", bet: "下注", call: "跟注", raise: "加注", allIn: "全押" };

const name = (id: string) => character(id).name;

/** 一条牌桌记录（从人类玩家的角度写；只用公开信息）。 */
export function logLine(e: TableEvent): string | null {
  switch (e.type) {
    case "handStart":
      return `—— 第 ${e.no} 手 · 底注 ${e.ante} · ${who(e.dealer)}坐庄 · ${who(e.chooser)}选场地 ——`;
    case "arenaChosen":
      return `${who(e.seat)}选了场地「${arena(e.arenaId).name}」`;
    case "placed":
      return `${who(e.seat)}排好了位，亮出 ${posName(e.revealPos)} ${name(e.characterId)}` +
        (e.eaten !== null ? `；饕餮吞掉了 ${posName(e.eaten)} 的队友` : "");
    case "peeked":
      return `${who(e.seat)}的窥视者偷看了${e.seat === HUMAN ? "对手" : "你"}一个暗置位置`;
    case "betAction": {
      const label = BET_LABEL[e.action] ?? e.action;
      return `第 ${e.round} 轮：${who(e.seat)}${label}${e.amount > 0 ? ` ${e.amount}` : ""}（奖池 ${e.pot}）`;
    }
    case "refund":
      return `退回${who(e.seat)}对方跟不上的 ${e.amount}`;
    case "operate": {
      const d = (s: Seat) => (e.drafted[s] ? `付 ${e.fee} 拿装备` : "不拿");
      return `操作：你${d(0)}，对手${d(1)}`;
    }
    case "installed": {
      const eq = equipment(e.equipmentId);
      return `${who(e.seat)}给 ${posName(e.pos)} 装上「${eq.name}」（${eq.text}）`;
    }
    case "reveal":
      return `翻开胜利规则「${rule(e.ruleId).name}」` +
        (e.publicEffectId ? `和公共效果「${publicEffect(e.publicEffectId).name}」` : "（已全押，公共效果不翻开）");
    case "votes":
      return `表决：你投${e.votes[0] ? "生效" : "不生效"}，对手投${e.votes[1] ? "生效" : "不生效"}`;
    case "bids":
      return `暗标：你出 ${e.bids[0]}，对手出 ${e.bids[1]}` +
        (e.bids[0] === e.bids[1] ? "，出价相同，谁都不付" : `，${who(e.bids[0] > e.bids[1] ? 0 : 1)}说了算并付出自己的出价`);
    case "peResult":
      return `公共效果「${publicEffect(e.publicEffectId).name}」${e.active ? "生效" : "不生效"}`;
    case "fold":
      return `${who(e.seat)}弃牌`;
    case "battle":
      return `战斗结束：${e.winner === null ? "平局" : `${who(e.winner)}获胜`}（${e.reason}）`;
    case "settle":
      return (e.winner === null ? "平局，双方拿回各自的投入" : `${who(e.winner)}赢得奖池 ${e.pot}`) +
        ` · 筹码：你 ${e.stacks[0]} / 对手 ${e.stacks[1]}`;
    case "market":
      return `市场翻出：${e.candidates.map(name).join("、")}；${who(e.firstPicker)}先挑`;
    case "marketPick":
      return `${who(e.seat)}挑走「${name(e.characterId)}」放进牌池`;
    case "marketRemove":
      return e.removed ? `${who(e.seat)}从牌池移除了一名人物` : null;
    case "tableOver":
      return `牌桌结束：${e.winner === HUMAN ? "你赢了！" : "对手赢了"}`;
  }
}

/** 一条战斗记录。names(seat, pos) 给出这个位置上的人物名。 */
export function battleLine(ev: BattleEvent, names: (seat: Seat, pos: number) => string): string {
  const u = (seat: Seat, pos: number) => `${seat === HUMAN ? "我方" : "敌方"}${posName(pos)}${names(seat, pos)}`;
  switch (ev.type) {
    case "attack":
      return `${u(ev.seat, ev.pos)} 攻击 ${u(ev.targetSeat, ev.targetPos)}` +
        (ev.segments.length > 1 ? `（${ev.segments.map(num).join(" + ")}）` : `（${num(ev.segments[0] ?? 0)}）`);
    case "blocked":
      return `${u(ev.seat, ev.pos)} 的屏障挡下一段`;
    case "damage":
      return `${u(ev.seat, ev.pos)} 失去 ${num(ev.amount)} 血，剩 ${num(Math.max(0, ev.hpAfter))}`;
    case "heal":
      return `${u(ev.seat, ev.pos)} 回复 ${num(ev.amount)} 血`;
    case "switch":
      return ev.remaining > 0
        ? `${u(ev.seat, ev.pos)} 对位已倒下，转线中（还要 ${ev.remaining} 轮）`
        : `${u(ev.seat, ev.pos)} 对位已倒下，这一轮用来转线`;
    case "death":
      return `${u(ev.seat, ev.pos)} 倒下`;
    case "note":
      return ev.text;
  }
}

export const REASON_TEXT: Record<BattleResult["reason"], string> = {
  达成规则: "达成胜利规则",
  "同时达成·比伤害": "双方同一轮达成，比这一轮造成的伤害",
  到时比较: "打满轮数，按规则比较",
  平局: "平局",
};

/** 规则说明（玩法页）。 */
export const HOW_TO_PLAY = `
<h3>目标</h3>
<p>1 对 1 的牌桌。每人 100 筹码，一手接一手打，把对手的筹码赢光就赢下牌桌。每 5 手底注翻倍。</p>
<h3>一手的流程</h3>
<ol>
  <li><b>底注</b>：双方各交底注进奖池。</li>
  <li><b>场地</b>：翻两张场地，筹码少的一方选一张（一样多时非庄家选）。</li>
  <li><b>排位</b>：从自己牌池随机发 4 名，挑 3 名排到 1、2、3 号位，并亮出其中 1 名。非庄家先排、先亮，庄家看到后再排。其余两名对手看不到。</li>
  <li><b>第 1 轮下注</b>：过牌、下注、跟注、加注、全押、弃牌，和德州扑克一样。</li>
  <li><b>操作</b>：下注匹配后，双方各自决定要不要付操作费（等于这一轮的下注额，最多不超过双方较少的筹码），付了就从 3 件装备里挑 1 件装到自己人身上。装备是公开的。</li>
  <li><b>翻牌</b>：翻开本手的胜利规则和 1 张公共效果。双方暗中表决公共效果要不要生效；意见不一致就暗标，出价高的一方说了算，只付自己的出价；出价相同则不生效。</li>
  <li><b>第 2 轮下注</b>，之后可以再操作一次。</li>
  <li><b>战斗</b>：揭开双方队伍，自动打完。谁达成胜利规则谁拿走奖池。</li>
  <li><b>市场</b>：翻 3 名人物，输家先挑一名放进牌池（挑了谁是公开的），然后双方可以暗中从牌池移除 1 名（牌池至少留 6 名）。</li>
</ol>
<h3>战斗</h3>
<ul>
  <li>双方同时出手，每人打自己的<b>对位</b>（同号位的敌人）。对位倒下后，要花一轮转线，然后改打敌方血最少的人。</li>
  <li><b>形状克制环</b>：重击 → 护甲 → 连击 → 屏障 → 重击。
    重击是一整段伤害，护甲每次只减一点，所以重击克护甲；
    连击把伤害分成两段，护甲每段都减，所以护甲克连击；
    屏障只挡一段，连击第二段照样打中，所以连击克屏障；
    屏障能挡掉整个重击，所以屏障克重击。</li>
  <li>护甲把每段伤害减到最少 0，但一次攻击只要打中，至少扣 1 血。屏障挡掉一段后消失，最多叠 2 层。</li>
  <li>每条胜利规则有自己的最多轮数，打满还没分出胜负就按规则比较。</li>
</ul>
<h3>诈唬</h3>
<p>对手只看得到你亮出的那一名、你的装备和你从市场挑了谁。你手里另外两名是谁、牌池里还有谁，全靠下注去讲故事。</p>
`;
