import { HeuristicAgent, type Style } from "../src/ai/agents.js";
import type { BattleResult } from "../src/battle/engine.js";
import type { UnitSnapshot } from "../src/battle/unit.js";
import { CHARACTERS, character } from "../src/content/characters.js";
import { ARENAS, EQUIPMENT, PUBLIC_EFFECTS, RULES, arena, equipment, publicEffect, rule } from "../src/content/tables.js";
import type { Action } from "../src/game/actions.js";
import { Table, validatePlacement, type Placement } from "../src/game/table.js";
import { legalActions, observe, type Observation } from "../src/game/view.js";
import type { Seat } from "../src/types.js";
import {
  AI, HOW_TO_PLAY, HUMAN, REASON_TEXT, SIN_COLOR, battleLine, esc, logLine, num, posName, shapeName, who,
} from "./text.js";

/**
 * 网页 demo：你（座位 0）对电脑（座位 1）。
 * 规则全部由核心驱动；这里只负责显示、收集点击、控制电脑出手的节奏和战斗回放。
 */

// ───────────────────────── 状态 ─────────────────────────

interface Playback {
  result: BattleResult;
  teams: [Placement, Placement];
  equipment: [(string | null)[], (string | null)[]];
  ruleId: string;
  arenaId: string;
  peId: string | null;
  /** 0 = 开战前，r = 第 r 轮结束后。 */
  step: number;
  auto: boolean;
}

interface Ui {
  /** 排位：slots[i] = 放在 i 号位的发牌序号。 */
  place: { slots: (number | null)[]; reveal: number | null; eaten: number | null };
  betAmount: number | null;
  draft: { offer: number | null; pos: number | null };
  bid: number;
  notice: string | null;
  error: string | null;
  battle: Playback | null;
  modal: "intro" | "help" | null;
  helpTab: "play" | "chars" | "rules" | "arenas" | "effects" | "equip";
  /** 最近一次战斗揭开的双方队伍（本手结束前用来亮出对手阵容）。 */
  lastBattle: { hand: number; teams: [Placement, Placement]; equipment: [(string | null)[], (string | null)[]] } | null;
}

const STYLE_NAME: Record<Style, string> = { cautious: "谨慎", aggressive: "激进", bluff: "爱诈唬" };

let table: Table;
let agent: HeuristicAgent;
let style: Style = "cautious";
let seed = 0;
let logLines: string[] = [];
let logCursor = 0;
let aiTimer: number | null = null;
let autoTimer: number | null = null;

const ui: Ui = {
  place: { slots: [null, null, null], reveal: null, eaten: null },
  betAmount: null,
  draft: { offer: null, pos: null },
  bid: 0,
  notice: null,
  error: null,
  battle: null,
  modal: "intro",
  helpTab: "play",
  lastBattle: null,
};

const app = document.getElementById("app")!;

function resetInputs() {
  ui.place = { slots: [null, null, null], reveal: null, eaten: null };
  ui.betAmount = null;
  ui.draft = { offer: null, pos: null };
  ui.bid = 0;
  ui.error = null;
}

function newTable(s: Style) {
  if (aiTimer !== null) clearTimeout(aiTimer);
  stopAuto();
  aiTimer = null;
  style = s;
  seed = Math.floor(Math.random() * 1e9);
  table = new Table({ seed });
  agent = new HeuristicAgent(style, seed + 1);
  logLines = [];
  logCursor = 0;
  ui.battle = null;
  ui.notice = null;
  ui.lastBattle = null;
  ui.modal = null;
  resetInputs();
  afterApply();
}

// ───────────────────────── 推进 ─────────────────────────

/** 每次有人提交动作后：读新增的牌桌记录，必要时打开战斗回放，然后重画并安排电脑。 */
function afterApply() {
  const fresh = table.log.slice(logCursor);
  logCursor = table.log.length;
  for (const e of fresh) {
    const line = logLine(e);
    if (line) logLines.push(line);
    if (e.type === "handStart") {
      ui.notice = null;
      ui.lastBattle = null;
      resetInputs();
    }
    if (e.type === "battle" && table.hand.battle) {
      const h = table.hand;
      ui.lastBattle = { hand: h.no, teams: e.teams, equipment: e.equipment };
      ui.battle = {
        result: table.hand.battle, teams: e.teams, equipment: e.equipment,
        ruleId: h.ruleId, arenaId: h.arenaId!, peId: h.peActive ? h.publicEffectId : null,
        step: 0, auto: true,
      };
    }
    if (e.type === "settle") {
      const by = table.hand.outcome?.by;
      const pot = e.pot;
      if (by === "fold") ui.notice = e.winner === HUMAN ? `对手弃牌，你赢得奖池 ${pot}` : `你弃牌，对手赢得奖池 ${pot}`;
      else ui.notice = e.winner === null ? "战斗平局，双方拿回投入" : e.winner === HUMAN ? `你赢下战斗，赢得奖池 ${pot}` : `对手赢下战斗，拿走奖池 ${pot}`;
    }
  }
  if (ui.battle?.auto) startAuto();
  render();
  scheduleAi();
}

function scheduleAi() {
  if (aiTimer !== null || ui.battle || ui.modal === "intro" || table.phase === "over") return;
  if (!table.toAct().includes(AI)) return;
  const delay = table.phase === "bet" ? 750 : table.phase === "place" ? 600 : 450;
  aiTimer = window.setTimeout(() => {
    aiTimer = null;
    if (ui.battle || !table.toAct().includes(AI)) return;
    let action: Action;
    try {
      action = agent.act(table, AI);
      table.apply(AI, action);
    } catch (err) {
      // 电脑出错时退回第一个合法动作，保证牌桌能继续
      console.error(err);
      table.apply(AI, legalActions(table, AI)[0]);
    }
    afterApply();
  }, delay);
  render();
}

function act(action: Action) {
  try {
    table.apply(HUMAN, action);
  } catch (err) {
    ui.error = err instanceof Error ? err.message : String(err);
    render();
    return;
  }
  resetInputs();
  afterApply();
}

// ───────────────────────── 战斗回放 ─────────────────────────

function startAuto() {
  stopAuto();
  autoTimer = window.setInterval(() => {
    const b = ui.battle;
    if (!b || !b.auto) return stopAuto();
    if (b.step >= b.result.timeline.length) {
      b.auto = false;
      stopAuto();
    } else {
      b.step++;
    }
    render();
  }, 1100);
}

function stopAuto() {
  if (autoTimer !== null) clearInterval(autoTimer);
  autoTimer = null;
}

function closeBattle() {
  stopAuto();
  ui.battle = null;
  render();
  scheduleAi();
}

// ───────────────────────── 画面：小部件 ─────────────────────────

function statLine(atk: number, hp: number, shape: "heavy" | "multi", armor: number, barrier: number) {
  return `<div class="c-stats"><span class="atk" title="攻">${num(atk)}</span><span class="sep">/</span><span class="hp" title="血">${num(hp)}</span></div>
    <div class="c-def"><span class="shape ${shape}">${shapeName(shape)}</span>${armor ? `<span class="armor">护甲 ${armor}</span>` : ""}${barrier ? `<span class="barrier">屏障 ${barrier}</span>` : ""}</div>`;
}

interface CardOpts {
  equip?: string | null;
  badge?: string;
  selected?: boolean;
  act?: string;
  arg?: string | number;
  compact?: boolean;
  dim?: boolean;
}

function attrs(o: { act?: string; arg?: string | number }) {
  return o.act ? ` data-act="${o.act}"${o.arg !== undefined ? ` data-arg="${o.arg}"` : ""} role="button" tabindex="0"` : "";
}

function card(id: string, o: CardOpts = {}) {
  const c = character(id);
  const eq = o.equip ? equipment(o.equip) : null;
  const cls = ["card", o.selected ? "selected" : "", o.compact ? "compact" : "", o.dim ? "dim" : "", o.act ? "clickable" : ""].join(" ");
  return `<div class="${cls}" style="--sin:${SIN_COLOR[c.sin]}"${attrs(o)}>
    ${o.badge ? `<span class="badge">${o.badge}</span>` : ""}
    <div class="c-top"><span class="c-name">${c.name}</span><span class="c-sin">${c.sin}</span></div>
    ${statLine(c.atk, c.hp, c.shape, c.armor, c.barrier)}
    <div class="c-tag">${c.tag}</div>
    ${o.compact ? "" : `<div class="c-ability">${esc(c.ability)}</div>`}
    ${eq ? `<div class="c-equip">⚙ ${eq.name}（${eq.text}）</div>` : ""}
  </div>`;
}

function backCard(text: string, o: CardOpts = {}) {
  const eq = o.equip ? equipment(o.equip) : null;
  return `<div class="card back ${o.act ? "clickable" : ""} ${o.selected ? "selected" : ""}"${attrs(o)}>
    ${o.badge ? `<span class="badge">${o.badge}</span>` : ""}
    <div class="back-mark">罪</div><div class="back-text">${text}</div>
    ${eq ? `<div class="c-equip">⚙ ${eq.name}（${eq.text}）</div>` : ""}
  </div>`;
}

function emptySlot(text: string, o: CardOpts = {}) {
  return `<div class="card empty ${o.act ? "clickable" : ""}"${attrs(o)}><div class="back-text">${text}</div></div>`;
}

function btn(label: string, act: string, arg?: string | number, extra = "") {
  return `<button data-act="${act}"${arg !== undefined ? ` data-arg="${arg}"` : ""} class="${extra}">${label}</button>`;
}

function infoBox(title: string, name: string | null, text: string, extra = "") {
  return `<div class="info ${name ? "" : "unknown"}"><div class="info-title">${title}</div>
    <div class="info-name">${name ?? "未翻开"}${extra}</div><div class="info-text">${text}</div></div>`;
}

// ───────────────────────── 画面：牌桌 ─────────────────────────

function render() {
  if (!table) {
    app.innerHTML = modalView();
    return;
  }
  const o = observe(table, HUMAN);
  app.innerHTML = `
    ${topBar(o)}
    <section class="infos">${infos(o)}</section>
    <section class="side foe">${foeHeader(o)}<div class="row">${foeRow(o)}</div></section>
    <div class="lanes"><span>1号位</span><span>2号位</span><span>3号位</span></div>
    <section class="side me"><div class="row">${myRow(o)}</div>${meHeader(o)}</section>
    ${ui.notice ? `<div class="notice">${ui.notice}</div>` : ""}
    <section class="panel">${ui.error ? `<div class="error">${esc(ui.error)}</div>` : ""}${panel(o)}</section>
    <section class="lower">${pools(o)}${logView()}</section>
    <footer class="foot">七罪暗队 · 规则草案 v0.3 试玩 · 牌桌种子 ${seed} · 电脑：${STYLE_NAME[style]}</footer>
    ${ui.battle ? battleView(ui.battle) : ""}
    ${ui.modal ? modalView() : ""}
  `;
}

function topBar(o: Observation) {
  return `<header class="top">
    <div class="title">七罪暗队 <small>v0.3 试玩</small></div>
    <div class="hand">第 ${o.handNo} 手 · 底注 ${o.ante} · 奖池 <b>${o.pot}</b></div>
    <div class="top-btns">${btn("规则", "help")}${btn("新牌桌", "intro")}</div>
  </header>`;
}

function infos(o: Observation) {
  const arenaBox = o.arenaId
    ? infoBox("场地", arena(o.arenaId).name, arena(o.arenaId).text)
    : infoBox("场地", null, `候选：${o.arenaOptions.map((a) => arena(a).name).join(" / ")}`);
  const r = o.ruleId ? rule(o.ruleId) : null;
  const ruleBox = r
    ? infoBox("胜利规则", r.name, r.text, ` <small>最多 ${r.maxRounds} 轮</small>`)
    : infoBox("胜利规则", null, "第 1 轮下注后翻开");
  let peBox: string;
  if (o.publicEffectId) {
    const pe = publicEffect(o.publicEffectId);
    const st = o.publicEffectActive === null ? "表决中" : o.publicEffectActive ? "生效" : "不生效";
    peBox = infoBox("公共效果", pe.name, pe.text, ` <small class="pe-${o.publicEffectActive}">${st}</small>`);
  } else {
    peBox = infoBox("公共效果", null, o.ruleId ? "已全押，本手没有公共效果" : "和胜利规则一起翻开");
  }
  return arenaBox + ruleBox + peBox;
}

function seatHeader(o: Observation, seat: Seat) {
  const dealer = o.dealer === seat ? `<span class="chip dealer">庄</span>` : "";
  const acting = o.toAct.includes(seat) && o.phase !== "over"
    ? `<span class="chip acting">${seat === HUMAN ? "轮到你" : "思考中…"}</span>` : "";
  const label = seat === HUMAN ? "你" : `电脑（${STYLE_NAME[style]}）`;
  const inRound = o.phase === "bet" ? ` · 本轮 ${o.betting.roundBet[seat]}` : "";
  return `<div class="seat-head"><span class="seat-name">${label}</span>${dealer}${acting}
    <span class="stack">筹码 <b>${o.stacks[seat]}</b></span><span class="invested">本手投入 ${o.invested[seat]}${inRound}</span></div>`;
}

function foeHeader(o: Observation) {
  const opp = o.opponent;
  const picks = opp.publicPicks.length ? `公开挑入：${opp.publicPicks.map((id) => character(id).name).join("、")}` : "还没从市场挑过人";
  return `${seatHeader(o, AI)}<div class="seat-sub">牌池 ${opp.poolSize} 名 · ${picks}${opp.removedCount ? ` · 移除过 ${opp.removedCount} 名` : ""}</div>`;
}

function meHeader(o: Observation) {
  return seatHeader(o, HUMAN);
}

function foeRow(o: Observation): string {
  const opp = o.opponent;
  const lb = ui.lastBattle && ui.lastBattle.hand === o.handNo ? ui.lastBattle : null;
  const peeking = o.phase === "peek" && o.toAct.includes(HUMAN);
  return [0, 1, 2].map((pos) => {
    const eq = opp.equipment[pos];
    if (lb) {
      const id = lb.teams[AI].slots[pos];
      return id ? card(id, { equip: lb.equipment[AI][pos], compact: true, badge: pos === lb.teams[AI].reveal ? "亮" : "揭开" }) : emptySlot("空位（被吞）");
    }
    if (!opp.placed) return backCard(o.phase === "arena" ? "等待发牌" : "排位中…");
    if (opp.emptyPositions.includes(pos)) return emptySlot("空位（被饕餮吞掉）");
    if (opp.revealed?.pos === pos) return card(opp.revealed.characterId, { equip: eq, compact: true, badge: "亮" });
    if (o.me.peek?.pos === pos) return card(o.me.peek.characterId, { equip: eq, compact: true, badge: "偷看" });
    if (peeking) return backCard("点这里偷看", { equip: eq, act: "peek", arg: pos });
    return backCard("暗置", { equip: eq });
  }).join("");
}

function myRow(o: Observation): string {
  const pl = o.me.placement;
  const placing = o.phase === "place" && o.toAct.includes(HUMAN);
  if (placing) {
    const dealt = o.me.dealt;
    return [0, 1, 2].map((pos) => {
      const i = ui.place.slots[pos];
      if (i === null) return emptySlot(`从下面挑一名放到${posName(pos)}`);
      if (ui.place.eaten === pos) return emptySlot(`被饕餮吞掉<br>（${character(dealt[i]).name}）`, { act: "unslot", arg: pos });
      const badge = ui.place.reveal === pos ? "亮" : "";
      return card(dealt[i], { compact: true, badge, act: "reveal", arg: pos, selected: ui.place.reveal === pos });
    }).join("");
  }
  if (!pl) {
    return [0, 1, 2].map(() => emptySlot(o.phase === "arena" ? "等待发牌" : "还没排位")).join("");
  }
  return pl.slots.map((id, pos) => {
    if (!id) return emptySlot("空位（被吞）");
    const drafting = o.phase === "draft" && o.me.offers && ui.draft.offer !== null;
    return card(id, {
      equip: o.me.equipment[pos], compact: true, badge: pos === pl.reveal ? "亮" : "暗",
      act: drafting ? "draftPos" : undefined, arg: pos, selected: drafting ? ui.draft.pos === pos : false,
    });
  }).join("");
}

// ───────────────────────── 画面：行动面板 ─────────────────────────

function panel(o: Observation): string {
  const mine = o.toAct.includes(HUMAN);
  switch (o.phase) {
    case "over": return overPanel();
    case "arena": return arenaPanel(o, mine);
    case "place": return placePanel(o, mine);
    case "peek": return mine
      ? `<h3>窥视者</h3><p>你的窥视者可以偷看对手一个暗置位置：点对手那一排里写着“点这里偷看”的牌。</p>`
      : waiting("对手的窥视者正在偷看你的一个暗置位置…");
    case "bet": return mine ? betPanel(o) : waiting(`对手正在考虑第 ${o.betting.round} 轮下注…`);
    case "operate": return mine ? operatePanel(o) : waiting("等待对手决定要不要拿装备…");
    case "draft": return mine && o.me.offers ? draftPanel(o) : waiting("对手正在挑装备…");
    case "vote": return mine ? votePanel(o) : waiting("等待对手表决…");
    case "bid": return mine ? bidPanel(o) : waiting("等待对手暗标出价…");
    case "marketPick": return marketPickPanel(o, mine);
    case "marketRemove": return mine ? removePanel(o) : waiting("等待对手整理牌池…");
  }
}

function waiting(text: string) {
  return `<p class="waiting">${text}</p>`;
}

function overPanel() {
  const won = table.winner === HUMAN;
  return `<div class="over ${won ? "won" : "lost"}"><h3>${won ? "你赢下了这张牌桌！" : "对手赢下了这张牌桌"}</h3>
    <p>共打了 ${table.handNo} 手。</p>${btn("再开一桌", "intro", undefined, "primary")}</div>`;
}

function arenaPanel(o: Observation, mine: boolean) {
  if (!mine) return waiting(`对手筹码较少（或同样多且不是庄家），由对手选场地…`);
  return `<h3>选场地</h3><p>你的筹码较少（或同样多且你不是庄家），由你从两张场地里选一张。</p>
    <div class="choices two">${o.arenaOptions.map((id, i) => {
      const a = arena(id);
      return `<div class="choice clickable" data-act="arena" data-arg="${i}" role="button" tabindex="0"><b>${a.name}</b><span class="kind">${a.kind}</span><p>${a.text}</p></div>`;
    }).join("")}</div>`;
}

function placePanel(o: Observation, mine: boolean) {
  const dealt = o.me.dealt;
  const dealtView = (clickable: boolean) => `<div class="dealt">${dealt.map((id, i) => {
    const at = ui.place.slots.indexOf(i);
    return card(id, { badge: clickable && at >= 0 ? posName(at) : "", selected: clickable && at >= 0, act: clickable ? "pick" : undefined, arg: i });
  }).join("")}</div>`;
  if (!mine) {
    const first = o.dealer === HUMAN;
    return `${waiting(first ? "对手不是庄家，先排位、先亮牌…" : "对手是庄家，看过你亮的牌后再排位…")}
      <p class="hint">你这手发到的 4 名：</p>${dealtView(false)}`;
  }
  const filled = ui.place.slots.every((x) => x !== null);
  const slotsIds = ui.place.slots.map((i) => (i === null ? null : dealt[i]));
  const gl2 = slotsIds.indexOf("GL2");
  const foeRevealed = o.opponent.revealed;
  let eatUi = "";
  if (gl2 >= 0 && filled) {
    const opts = [0, 1, 2].filter((p) => p !== gl2);
    eatUi = `<div class="row-btns"><span>饕餮（${posName(gl2)}）吞掉一名队友，获得它的攻和血：</span>
      ${btn("不吞", "eat", -1, ui.place.eaten === null ? "on" : "")}
      ${opts.map((p) => btn(`吞 ${posName(p)} ${character(slotsIds[p]!).name}`, "eat", p, ui.place.eaten === p ? "on" : "")).join("")}</div>`;
  }
  let ok = false;
  let why = "";
  if (!filled) why = "先挑 3 名排好位";
  else if (ui.place.reveal === null) why = "选择亮出谁";
  else {
    try {
      validatePlacement(dealt, ui.place.slots as number[], ui.place.eaten !== null ? { eater: gl2, eaten: ui.place.eaten } : null, ui.place.reveal);
      ok = true;
    } catch (err) {
      why = err instanceof Error ? err.message : String(err);
    }
  }
  const revealName = ok ? `${posName(ui.place.reveal!)} ${character(slotsIds[ui.place.reveal!]!).name}` : "";
  return `<h3>排位</h3>
    <p>${o.dealer === HUMAN ? "你是庄家，后排位：" : "你不是庄家，先排位：对手会先看到你亮的那一名。"}
    依次点下面的牌放到 1、2、3 号位（再点一次取消），然后选一名<b>亮出</b>。${foeRevealed ? `对手亮出的是 ${posName(foeRevealed.pos)} ${character(foeRevealed.characterId).name}。` : ""}</p>
    ${dealtView(true)}${eatUi}
    ${filled ? `<div class="row-btns"><span>亮出：</span>${[0, 1, 2].filter((p) => p !== ui.place.eaten).map((p) => btn(`${posName(p)} ${character(slotsIds[p]!).name}`, "reveal", p, ui.place.reveal === p ? "on" : "")).join("")}</div>` : ""}
    <div class="row-btns">${ok ? btn(`确认排位（亮出 ${revealName}）`, "place", undefined, "primary") : `<span class="hint">${why}</span>`}
    ${ui.place.slots.some((x) => x !== null) ? btn("清空", "clearPlace") : ""}</div>`;
}

function betPanel(o: Observation) {
  const b = o.betting;
  const stack = o.stacks[HUMAN];
  const me = b.roundBet[HUMAN];
  const acts = legalActions(table, HUMAN);
  const has = (t: Action["type"]) => acts.some((a) => a.type === t);
  const opening = b.target === 0;
  const min = opening ? table.options.minBet : b.minRaiseTo;
  const max = opening ? stack - 1 : me + stack - 1;
  const canSize = min <= max;
  if (canSize && (ui.betAmount === null || ui.betAmount < min || ui.betAmount > max)) ui.betAmount = min;
  const quick = acts.flatMap((a) => (a.type === "bet" ? [a.amount] : a.type === "raise" ? [a.to] : []));
  const verb = opening ? "下注" : "加注到";
  const lines = [
    `第 ${b.round} 轮下注 · 奖池 ${o.pot} · 你本轮已下 ${me} · 对手本轮 ${b.roundBet[AI]}` + (b.toCall ? ` · <b>需跟 ${Math.min(b.toCall, stack)}</b>` : ""),
  ];
  if (!b.canFold) lines.push(`<span class="warn">对手亮出了冠冕者：第 1 轮下注你不能弃牌</span>`);
  return `<h3>下注</h3><p>${lines.join("<br>")}</p>
    <div class="row-btns">
      ${has("check") ? btn("过牌", "check") : ""}
      ${has("call") ? btn(`跟注 ${Math.min(b.toCall, stack)}`, "call") : ""}
      ${has("fold") ? btn("弃牌", "fold", undefined, "danger") : ""}
      ${has("allIn") ? btn(`全押 ${stack}`, "allIn", undefined, "danger") : ""}
    </div>
    ${canSize ? `<div class="sizer">
      <span>${verb}</span>
      <input type="range" min="${min}" max="${max}" step="1" value="${ui.betAmount}" data-input="bet">
      <input type="number" min="${min}" max="${max}" step="1" value="${ui.betAmount}" data-input="bet">
      ${quick.map((x) => btn(String(x), "setBet", x, "small")).join("")}
      ${btn(`${verb} <b data-bind="bet">${ui.betAmount}</b>`, "betSized", undefined, "primary")}
    </div>` : ""}`;
}

function operatePanel(o: Observation) {
  return `<h3>操作</h3><p>下注已经匹配。付 <b>${o.opFee}</b> 操作费，就能从 3 件随机装备里挑 1 件装到自己人身上（对手看得到装在哪）。
    ${o.opponent.submitted ? "对手已经决定了。" : ""}</p>
    <div class="row-btns">${btn(`付 ${o.opFee} 拿装备`, "operate", 1, "primary")}${btn("不拿", "operate", 0)}</div>`;
}

function draftPanel(o: Observation) {
  const offers = o.me.offers!;
  const pl = o.me.placement!;
  const ready = ui.draft.offer !== null && ui.draft.pos !== null;
  return `<h3>挑装备</h3><p>先选一件装备，再选择装给谁。</p>
    <div class="choices three">${offers.map((id, i) => {
      const e = equipment(id);
      return `<div class="choice clickable ${ui.draft.offer === i ? "selected" : ""}" data-act="draftOffer" data-arg="${i}" role="button" tabindex="0"><b>${e.name}</b><p>${e.text}</p></div>`;
    }).join("")}</div>
    ${ui.draft.offer !== null ? `<div class="row-btns"><span>装给：</span>${pl.slots.map((id, pos) => (id ? btn(`${posName(pos)} ${character(id).name}`, "draftPos", pos, ui.draft.pos === pos ? "on" : "") : "")).join("")}</div>` : ""}
    <div class="row-btns">${ready ? btn(`确认：把「${equipment(offers[ui.draft.offer!]).name}」装到 ${posName(ui.draft.pos!)}`, "draft", undefined, "primary") : ""}</div>`;
}

function votePanel(o: Observation) {
  const pe = publicEffect(o.publicEffectId!);
  return `<h3>公共效果表决</h3><p>「<b>${pe.name}</b>」：${pe.text}</p>
    <p class="hint">双方暗中投票。一致就照办；不一致就暗标，出价高的一方说了算，只付自己的出价；出价相同则不生效。${o.opponent.submitted ? "对手已经投了。" : ""}</p>
    <div class="row-btns">${btn("投：生效", "vote", 1, "primary")}${btn("投：不生效", "vote", 0)}</div>`;
}

function bidPanel(o: Observation) {
  const cap = o.bidCap;
  if (ui.bid > cap) ui.bid = cap;
  const quick = [...new Set([0, 5, 10, 20, Math.floor(cap / 2), cap].filter((x) => x <= cap))].sort((a, b) => a - b);
  return `<h3>暗标</h3><p>你投了<b>${o.me.vote ? "生效" : "不生效"}</b>，对手投了相反的票。出价高的一方说了算，只付自己的出价（算作本手投入）；出价相同则不生效、都不付。最多 ${cap}。
    ${o.opponent.submitted ? "对手已经出价了。" : ""}</p>
    <div class="sizer"><span>出价</span>
      <input type="range" min="0" max="${cap}" step="1" value="${ui.bid}" data-input="bid">
      <input type="number" min="0" max="${cap}" step="1" value="${ui.bid}" data-input="bid">
      ${quick.map((x) => btn(String(x), "setBid", x, "small")).join("")}
      ${btn(`出价 <b data-bind="bid">${ui.bid}</b>`, "bid", undefined, "primary")}
    </div>`;
}

function marketPickPanel(o: Observation, mine: boolean) {
  const stage = Table.marketStageFor(o.handNo, table.options.blindEvery);
  const head = `<h3>市场</h3><p>本手的输家先挑一名放进牌池，另一方再从剩下的里挑。挑了谁是公开的。市场阶段 ${stage}。</p>`;
  const cards = `<div class="dealt">${o.market.map((id, i) => card(id, { act: mine ? "marketPick" : undefined, arg: i })).join("")}</div>`;
  return head + (mine ? `<p><b>轮到你挑：</b>点一名。</p>` : waiting("对手正在挑…")) + cards;
}

function removePanel(o: Observation) {
  const pool = o.me.pool;
  const canRemove = pool.length - 1 >= table.options.minPoolSize;
  return `<h3>整理牌池</h3><p>可以暗中从牌池移除 1 名（牌池至少留 ${table.options.minPoolSize} 名），也可以不移除。
    ${canRemove ? "点一名移除：" : "牌池已经是下限，不能再移除。"}</p>
    ${canRemove ? `<div class="pool">${pool.map((id, i) => card(id, { compact: true, act: "remove", arg: i })).join("")}</div>` : ""}
    <div class="row-btns">${btn("不移除，开始下一手", "remove", -1, "primary")}</div>`;
}

function pools(o: Observation) {
  return `<details class="box"><summary>我的牌池（${o.me.pool.length} 名）</summary>
    <div class="pool">${o.me.pool.map((id) => card(id, { compact: true })).join("")}</div></details>`;
}

function logView() {
  const lines = logLines.slice(-80).reverse();
  return `<details class="box" open><summary>牌桌记录</summary><ol class="log">${lines.map((l) => `<li class="${l.startsWith("——") ? "sep" : ""}">${esc(l)}</li>`).join("")}</ol></details>`;
}

// ───────────────────────── 画面：战斗回放 ─────────────────────────

function battleView(b: Playback) {
  const r = b.result;
  const total = r.timeline.length;
  const snap: [UnitSnapshot[], UnitSnapshot[]] = b.step === 0 ? r.start : r.timeline[b.step - 1];
  const names = (seat: Seat, pos: number) => {
    const id = r.start[seat][pos].characterId;
    return id ? character(id).name : "空位";
  };
  const evs = b.step === 0 ? [] : r.events.filter((e) => e.round === b.step);
  const hit = new Set(evs.filter((e) => e.type === "damage").map((e) => `${e.seat}-${e.pos}`));
  const died = new Set(evs.filter((e) => e.type === "death").map((e) => `${e.seat}-${e.pos}`));
  const unit = (u: UnitSnapshot) => {
    if (!u.characterId) return `<div class="unit empty">空位</div>`;
    const c = character(u.characterId);
    const pct = Math.max(0, Math.min(100, (u.hp / u.startHp) * 100));
    const eq = b.equipment[u.seat][u.pos];
    const k = `${u.seat}-${u.pos}`;
    return `<div class="unit ${u.alive ? "" : "dead"} ${hit.has(k) ? "hit" : ""} ${died.has(k) ? "died" : ""}" style="--sin:${SIN_COLOR[c.sin]}">
      <div class="u-name">${c.name}${b.teams[u.seat].reveal === u.pos ? `<span class="mini">亮</span>` : ""}</div>
      <div class="u-stats"><span class="atk">${num(u.atk)}</span>/<span class="hp">${num(Math.max(0, u.hp))}</span></div>
      ${u.alive ? `<div class="bar"><i style="width:${pct}%"></i></div>` : `<div class="u-dead">倒下</div>`}
      <div class="u-def"><span class="shape ${u.shape}">${shapeName(u.shape)}</span>${u.armor ? `<span class="armor">甲${u.armor}</span>` : ""}${u.barrier ? `<span class="barrier">障${u.barrier}</span>` : ""}</div>
      ${eq ? `<div class="u-eq">⚙ ${equipment(eq).name}</div>` : ""}
    </div>`;
  };
  const done = b.step >= total;
  const resultText = r.winner === null ? "平局" : r.winner === HUMAN ? "你赢了这场战斗" : "对手赢了这场战斗";
  const ru = rule(b.ruleId);
  return `<div class="overlay"><div class="battle" role="dialog" aria-label="战斗回放">
    <div class="b-head"><b>战斗</b> · 规则「${ru.name}」<small>${ru.text}</small></div>
    <div class="b-env">场地「${arena(b.arenaId).name}」：${arena(b.arenaId).text}${b.peId ? `<br>公共效果「${publicEffect(b.peId).name}」：${publicEffect(b.peId).text}` : "<br>没有生效的公共效果"}</div>
    <div class="b-round">${b.step === 0 ? "开战前（开战效果已结算）" : `第 ${b.step} 轮`} <small>/ 共 ${total} 轮，本规则最多 ${ru.maxRounds} 轮</small></div>
    <div class="b-label">对手</div>
    <div class="b-row">${snap[AI].map(unit).join("")}</div>
    <div class="b-row">${snap[HUMAN].map(unit).join("")}</div>
    <div class="b-label">你</div>
    <ol class="b-events">${evs.length ? evs.map((e) => `<li class="ev-${e.type}">${esc(battleLine(e, names))}</li>`).join("") : `<li class="hint">${b.step === 0 ? "双方揭开队伍。" : "这一轮没有人出手。"}</li>`}</ol>
    ${done ? `<div class="b-result ${r.winner === HUMAN ? "won" : r.winner === null ? "" : "lost"}">${resultText} · ${REASON_TEXT[r.reason]}</div>` : ""}
    <div class="b-controls">
      ${btn("上一轮", "bPrev", undefined, b.step === 0 ? "disabled" : "")}
      ${btn(b.auto ? "暂停" : "自动播放", "bAuto", undefined, done ? "disabled" : "")}
      ${btn("下一轮", "bNext", undefined, done ? "disabled" : "")}
      ${done ? btn("继续", "bClose", undefined, "primary") : btn("跳到结果", "bEnd")}
    </div>
  </div></div>`;
}

// ───────────────────────── 画面：弹窗 ─────────────────────────

function modalView() {
  if (ui.modal === "intro") {
    return `<div class="overlay"><div class="modal intro" role="dialog" aria-label="开始">
      <h2>七罪暗队 <small>v0.3 试玩</small></h2>
      <p>德州扑克的下注 + 酒馆战棋的身材和自动战斗。每手从自己的牌池里排出 3 名人物，只亮 1 名，靠下注讲故事，揭开后自动打一场。</p>
      <p>你和电脑各 100 筹码，赢光对方就赢下牌桌。第一次玩可以先看看“规则”。</p>
      <p><b>选择电脑对手：</b></p>
      <div class="row-btns">${btn("谨慎", "start", "cautious", "primary")}${btn("激进", "start", "aggressive")}${btn("爱诈唬", "start", "bluff")}</div>
      <div class="row-btns">${btn("先看规则", "help")}${table ? btn("回到当前牌桌", "closeModal") : ""}</div>
    </div></div>`;
  }
  const tabs: Array<[Ui["helpTab"], string]> = [["play", "玩法"], ["chars", "人物"], ["equip", "装备"], ["rules", "胜利规则"], ["arenas", "场地"], ["effects", "公共效果"]];
  let body = "";
  switch (ui.helpTab) {
    case "play": body = HOW_TO_PLAY; break;
    case "chars": body = `<p class="hint">开桌时每人的牌池从全部人物里随机 8 名。市场里，第 1–5 手只出没有标记的人物，第 6 手起只出标“第二阶段”的人物。</p><div class="pool">${CHARACTERS.map((c) => card(c.id, { badge: c.stage === 2 ? "第二阶段" : "" })).join("")}</div>`; break;
    case "equip": body = refTable(EQUIPMENT.map((e) => [e.name, e.text])); break;
    case "rules": body = refTable(RULES.map((r) => [`${r.name}<br><small>${r.family} · 最多 ${r.maxRounds} 轮</small>`, r.text])); break;
    case "arenas": body = refTable(ARENAS.map((a) => [`${a.name}<br><small>${a.kind}</small>`, a.text])); break;
    case "effects": body = refTable(PUBLIC_EFFECTS.map((p) => [`${p.name}<br><small>${p.kind}</small>`, p.text])); break;
  }
  return `<div class="overlay"><div class="modal help" role="dialog" aria-label="规则">
    <div class="tabs">${tabs.map(([k, l]) => btn(l, "tab", k, ui.helpTab === k ? "on" : "")).join("")}${btn("关闭", "closeModal", undefined, "close")}</div>
    <div class="help-body">${body}</div>
  </div></div>`;
}

function refTable(rows: Array<[string, string]>) {
  return `<table class="ref">${rows.map(([a, b]) => `<tr><th>${a}</th><td>${b}</td></tr>`).join("")}</table>`;
}

// ───────────────────────── 输入 ─────────────────────────

function onAct(name: string, arg: string | undefined) {
  const n = arg === undefined ? NaN : Number(arg);
  const o = table && table.phase !== "over" ? observe(table, HUMAN) : null;
  switch (name) {
    case "intro": ui.modal = "intro"; return render();
    case "help": ui.modal = "help"; return render();
    case "closeModal": ui.modal = table ? null : "intro"; render(); return scheduleAi();
    case "tab": ui.helpTab = arg as Ui["helpTab"]; return render();
    case "start": return newTable(arg as Style);
    case "arena": return act({ type: "chooseArena", index: n as 0 | 1 });
    case "pick": {
      const at = ui.place.slots.indexOf(n);
      if (at >= 0) {
        ui.place.slots[at] = null;
        if (ui.place.reveal === at) ui.place.reveal = null;
      } else {
        const free = ui.place.slots.indexOf(null);
        if (free < 0) { ui.error = "3 个位置都排满了，先点一张已排的牌取消"; return render(); }
        ui.place.slots[free] = n;
      }
      ui.place.eaten = null;
      ui.error = null;
      return render();
    }
    case "unslot": ui.place.eaten = null; return render();
    case "reveal": ui.place.reveal = n; ui.error = null; return render();
    case "eat": ui.place.eaten = n < 0 ? null : n; if (ui.place.reveal === ui.place.eaten) ui.place.reveal = null; return render();
    case "clearPlace": resetInputs(); return render();
    case "place": {
      const slots = ui.place.slots as number[];
      const gl2 = slots.findIndex((i) => o!.me.dealt[i] === "GL2");
      return act({
        type: "place", picks: [slots[0], slots[1], slots[2]], reveal: ui.place.reveal!,
        eat: ui.place.eaten !== null ? { eater: gl2, eaten: ui.place.eaten } : null,
      });
    }
    case "peek": return act({ type: "peek", pos: n });
    case "check": return act({ type: "check" });
    case "call": return act({ type: "call" });
    case "fold": return act({ type: "fold" });
    case "allIn": return act({ type: "allIn" });
    case "setBet": ui.betAmount = n; return render();
    case "betSized": {
      const amount = ui.betAmount!;
      return act(o!.betting.target === 0 ? { type: "bet", amount } : { type: "raise", to: amount });
    }
    case "operate": return act({ type: "operate", draft: n === 1 });
    case "draftOffer": ui.draft.offer = n; return render();
    case "draftPos": ui.draft.pos = n; return render();
    case "draft": return act({ type: "draft", offerIndex: ui.draft.offer!, pos: ui.draft.pos! });
    case "vote": return act({ type: "vote", activate: n === 1 });
    case "setBid": ui.bid = n; return render();
    case "bid": return act({ type: "bid", amount: ui.bid });
    case "marketPick": return act({ type: "marketPick", index: n });
    case "remove": return act({ type: "marketRemove", poolIndex: n < 0 ? null : n });
    case "bPrev": if (ui.battle) { ui.battle.auto = false; stopAuto(); ui.battle.step = Math.max(0, ui.battle.step - 1); } return render();
    case "bNext": if (ui.battle) { ui.battle.auto = false; stopAuto(); ui.battle.step = Math.min(ui.battle.result.timeline.length, ui.battle.step + 1); } return render();
    case "bEnd": if (ui.battle) { ui.battle.auto = false; stopAuto(); ui.battle.step = ui.battle.result.timeline.length; } return render();
    case "bAuto": if (ui.battle) { ui.battle.auto = !ui.battle.auto; if (ui.battle.auto) startAuto(); else stopAuto(); } return render();
    case "bClose": return closeBattle();
  }
}

app.addEventListener("click", (ev) => {
  const el = (ev.target as HTMLElement).closest<HTMLElement>("[data-act]");
  if (!el || el.classList.contains("disabled")) return;
  onAct(el.dataset.act!, el.dataset.arg);
});

app.addEventListener("keydown", (ev) => {
  if (ev.key !== "Enter" && ev.key !== " ") return;
  const el = (ev.target as HTMLElement).closest<HTMLElement>("[data-act][role=button]");
  if (!el) return;
  ev.preventDefault();
  onAct(el.dataset.act!, el.dataset.arg);
});

// 滑块和数字框：只更新数字，不整页重画（否则拖动会中断）
app.addEventListener("input", (ev) => {
  const el = ev.target as HTMLInputElement;
  const key = el.dataset.input;
  if (!key) return;
  const v = Math.round(Number(el.value));
  if (!Number.isFinite(v)) return;
  if (key === "bet") ui.betAmount = v;
  if (key === "bid") ui.bid = v;
  app.querySelectorAll<HTMLInputElement>(`[data-input="${key}"]`).forEach((x) => { if (x !== el) x.value = String(v); });
  app.querySelectorAll(`[data-bind="${key}"]`).forEach((x) => { x.textContent = String(v); });
});

render();

// 给自动化测试用：读当前牌桌（不影响游戏）
(window as unknown as { __sinSquad: unknown }).__sinSquad = {
  get table() { return table; },
  get ui() { return ui; },
};
