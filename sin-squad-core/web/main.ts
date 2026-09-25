import { HeuristicAgent, type Style } from "../src/ai/agents.js";
import type { BattleEvent, BattleResult } from "../src/battle/engine.js";
import type { UnitSnapshot } from "../src/battle/unit.js";
import { CHARACTERS, character } from "../src/content/characters.js";
import { ARENAS, EQUIPMENT, PUBLIC_EFFECTS, RULES, arena, equipment, publicEffect, rule } from "../src/content/tables.js";
import type { Action } from "../src/game/actions.js";
import { Table, validatePlacement, type Placement } from "../src/game/table.js";
import { legalActions, observe, type Observation } from "../src/game/view.js";
import type { AttackShape, Seat } from "../src/types.js";
import {
  AI, CARD_TEXT, HOW_TO_PLAY, HUMAN, REASON_TEXT, SIN_COLOR, SIN_GLYPH, battleLine, esc, logLine, num, posName, shapeName,
} from "./text.js";

/**
 * 网页 demo：你（座位 0）对电脑（座位 1）。
 * 规则全部由核心驱动；这里只负责显示、收集点击、控制电脑出手的节奏和战斗动画。
 *
 * 画面是一张固定在一屏里的牌桌：上面对手，中间桌面（场地 / 规则 / 公共效果、奖池），下面我方，
 * 最底下是操作栏。战斗直接在桌面上演。
 */

// ───────────────────────── 状态 ─────────────────────────

interface Playback {
  result: BattleResult;
  teams: [Placement, Placement];
  equipment: [(string | null)[], (string | null)[]];
  ruleId: string;
  arenaId: string;
  peId: string | null;
  /** 画面上此刻显示的双方样子。 */
  snap: [UnitSnapshot[], UnitSnapshot[]];
  /** 当前播到第几轮（0 = 开战前）。 */
  round: number;
  /** 正在出手的人（seat-pos），高亮用。 */
  actor: string | null;
  started: boolean;
  paused: boolean;
  speed: 1 | 2;
  caption: string[];
  done: boolean;
}

type Sheet =
  | { kind: "intro" }
  | { kind: "help" }
  | { kind: "card"; id: string; equip: string | null }
  | { kind: "env"; which: "arena" | "rule" | "pe" }
  | { kind: "log" }
  | { kind: "pool" };

interface Ui {
  /** 排位：slots[i] = 放在 i 号位的发牌序号。 */
  place: { slots: (number | null)[]; reveal: number | null; eaten: number | null };
  betAmount: number | null;
  draft: { offer: number | null; pos: number | null };
  bid: number;
  removeIdx: number | null;
  notice: { text: string; good: boolean | null } | null;
  error: string | null;
  battle: Playback | null;
  sheet: Sheet | null;
  helpTab: "play" | "chars" | "rules" | "arenas" | "effects" | "equip";
  /** 本手打完的战斗（市场阶段继续在桌上摆出双方最后的样子）。 */
  lastBattle: { hand: number; result: BattleResult; teams: [Placement, Placement]; equipment: [(string | null)[], (string | null)[]] } | null;
}

/** 有立绘的人物（打包时由 scripts/build-web.mjs 根据 web/art/ 填入）。 */
declare const __ART_IDS__: string[];
const ART = new Set<string>(typeof __ART_IDS__ === "undefined" ? [] : __ART_IDS__);

const STYLE_NAME: Record<Style, string> = { cautious: "谨慎", aggressive: "激进", bluff: "爱诈唬" };

let table: Table | null = null;
let agent: HeuristicAgent;
let style: Style = "cautious";
let seed = 0;
let logLines: string[] = [];
let logCursor = 0;
let aiTimer: number | null = null;
let battleToken = 0;

const ui: Ui = {
  place: { slots: [null, null, null], reveal: null, eaten: null },
  betAmount: null,
  draft: { offer: null, pos: null },
  bid: 0,
  removeIdx: null,
  notice: null,
  error: null,
  battle: null,
  sheet: { kind: "intro" },
  helpTab: "play",
  lastBattle: null,
};

const app = document.getElementById("app")!;
const sleep = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));

function resetInputs() {
  ui.place = { slots: [null, null, null], reveal: null, eaten: null };
  ui.betAmount = null;
  ui.draft = { offer: null, pos: null };
  ui.bid = 0;
  ui.removeIdx = null;
  ui.error = null;
}

function newTable(s: Style) {
  if (aiTimer !== null) clearTimeout(aiTimer);
  aiTimer = null;
  battleToken++;
  style = s;
  seed = Math.floor(Math.random() * 1e9);
  table = new Table({ seed });
  agent = new HeuristicAgent(style, seed + 1);
  logLines = [];
  logCursor = 0;
  ui.battle = null;
  ui.notice = null;
  ui.lastBattle = null;
  ui.sheet = null;
  resetInputs();
  afterApply();
}

// ───────────────────────── 推进 ─────────────────────────

/** 每次有人提交动作后：读新增的牌桌记录，必要时开始战斗动画，然后重画并安排电脑。 */
function afterApply() {
  const t = table!;
  const fresh = t.log.slice(logCursor);
  logCursor = t.log.length;
  for (const e of fresh) {
    const line = logLine(e);
    if (line) logLines.push(line);
    if (e.type === "handStart") {
      ui.notice = null;
      ui.lastBattle = null;
      resetInputs();
    }
    if (e.type === "battle" && t.hand.battle) {
      const h = t.hand;
      ui.lastBattle = { hand: h.no, result: h.battle!, teams: e.teams, equipment: e.equipment };
      ui.battle = {
        result: h.battle!, teams: e.teams, equipment: e.equipment,
        ruleId: h.ruleId, arenaId: h.arenaId!, peId: h.peActive ? h.publicEffectId : null,
        snap: h.battle!.start, round: 0, actor: null, started: false,
        paused: false, speed: 1, caption: ["揭开双方队伍"], done: false,
      };
    }
    if (e.type === "settle") {
      const pot = e.pot;
      if (t.hand.outcome?.by === "fold") {
        ui.notice = e.winner === HUMAN ? { text: `对手弃牌 · 你拿下奖池 ${pot}`, good: true } : { text: `你弃牌 · 对手拿下奖池 ${pot}`, good: false };
      } else {
        ui.notice = e.winner === null ? { text: "平局 · 双方拿回投入", good: null }
          : e.winner === HUMAN ? { text: `你赢下战斗 · 拿下奖池 ${pot}`, good: true } : { text: `对手赢下战斗 · 拿走奖池 ${pot}`, good: false };
      }
    }
  }
  render();
  if (ui.battle && !ui.battle.started) { ui.battle.started = true; void playBattle(ui.battle); }
  scheduleAi();
}

function scheduleAi() {
  const t = table;
  if (!t || aiTimer !== null || ui.battle || ui.sheet?.kind === "intro" || t.phase === "over") return;
  if (!t.toAct().includes(AI)) return;
  const delay = t.phase === "bet" ? 800 : t.phase === "place" ? 700 : 500;
  aiTimer = window.setTimeout(() => {
    aiTimer = null;
    if (ui.battle || !t.toAct().includes(AI) || t !== table) return;
    try {
      t.apply(AI, agent.act(t, AI));
    } catch (err) {
      // 电脑出错时退回第一个合法动作，保证牌桌能继续
      console.error(err);
      t.apply(AI, legalActions(t, AI)[0]);
    }
    afterApply();
  }, delay);
}

function act(action: Action) {
  try {
    table!.apply(HUMAN, action);
  } catch (err) {
    ui.error = err instanceof Error ? err.message : String(err);
    render();
    return;
  }
  resetInputs();
  afterApply();
}

// ───────────────────────── 战斗动画 ─────────────────────────

const unitEl = (seat: Seat, pos: number) => app.querySelector<HTMLElement>(`[data-unit="${seat}-${pos}"]`);

function floater(seat: Seat, pos: number, text: string, cls: string, delay = 0) {
  const el = unitEl(seat, pos);
  if (!el) return;
  const f = document.createElement("span");
  f.className = `floater ${cls}`;
  f.textContent = text;
  f.style.animationDelay = `${delay}ms`;
  el.appendChild(f);
}

function lunge(from: HTMLElement | null, to: HTMLElement | null, ms: number) {
  if (!from || !to || !from.animate) return;
  const a = from.getBoundingClientRect();
  const b = to.getBoundingClientRect();
  const dx = (b.left + b.width / 2 - (a.left + a.width / 2)) * 0.42;
  const dy = (b.top + b.height / 2 - (a.top + a.height / 2)) * 0.42;
  from.animate(
    [{ transform: "none", zIndex: 5 }, { transform: `translate(${dx}px, ${dy}px) scale(1.06)`, zIndex: 5 }, { transform: "none", zIndex: 5 }],
    { duration: ms, easing: "ease-in-out" },
  );
}

function unitNames(b: Playback) {
  return (seat: Seat, pos: number) => {
    const id = b.result.start[seat][pos].characterId;
    return id ? character(id).name : "空位";
  };
}

/** 一帧的字幕：出手、反击、屏障、转线、能力生效、倒下。 */
function frameCaption(b: Playback, evs: BattleEvent[]): string[] {
  const names = unitNames(b);
  const shown = evs.filter((e) => ["attack", "recoil", "blocked", "switch", "trigger", "death", "note"].includes(e.type));
  return shown.map((e) => battleLine(e, names));
}

/** 能力 / 场地 / 公共效果生效：卡片闪一下，头上冒出说明气泡。 */
function bubble(e: Extract<BattleEvent, { type: "trigger" }>, own: boolean) {
  const el = unitEl(e.seat, e.pos);
  if (!el) return;
  el.classList.remove("proc");
  void el.offsetWidth; // 让闪光动画可以重播
  el.classList.add("proc");
  const d = document.createElement("div");
  d.className = `bubble ${own ? "own" : "env"}`;
  d.innerHTML = own ? esc(e.text) : `<small>${esc(e.name)}</small>${esc(e.text)}`;
  el.appendChild(d);
}

/** 第 r 轮谁先手。 */
function firstOf(b: Playback, r: number): Seat {
  return r % 2 === 1 ? b.result.first : (b.result.first === 0 ? 1 : 0);
}

/**
 * 逐帧播放：每一帧是一次出手（或轮初、轮末的效果）。
 * 先播出手前的提示和冲撞，再换成这一帧结束时的样子，飘伤害数字，最后播结算后才生效的能力。
 */
async function playBattle(b: Playback) {
  const token = ++battleToken;
  const alive = () => token === battleToken && ui.battle === b;
  const wait = async (ms: number) => {
    await sleep(ms / b.speed);
    while (alive() && b.paused) await sleep(100);
  };
  const names = unitNames(b);
  const isOwn = (e: Extract<BattleEvent, { type: "trigger" }>) => names(e.seat, e.pos) === e.name;
  render();
  await wait(1000); // 翻牌

  for (const f of b.result.frames) {
    if (!alive()) return;
    const setup = f.round === 0;
    if (f.round !== b.round) {
      b.round = f.round;
      if (!setup) {
        b.caption = [`第 ${f.round} 轮 · ${firstOf(b, f.round) === HUMAN ? "你" : "对手"}先手`];
        b.actor = null;
        render();
        await wait(650);
      }
    }
    const attack = f.events.find((e) => e.type === "attack" || e.type === "switch");
    b.actor = attack ? `${attack.seat}-${attack.pos}` : null;
    b.caption = [setup ? "开战" : `第 ${f.round} 轮`, ...frameCaption(b, f.events)];
    render();

    const firstHit = f.events.findIndex((e) => e.type === "damage" || e.type === "death" || e.type === "heal");
    const cut = firstHit < 0 ? f.events.length : firstHit;
    for (const e of f.events.slice(0, cut)) {
      if (!alive()) return;
      if (e.type === "trigger") { bubble(e, isOwn(e)); await wait(setup ? 850 : 380); }
      if (e.type === "attack") { lunge(unitEl(e.seat, e.pos), unitEl(e.targetSeat, e.targetPos), 460 / b.speed); await wait(260); }
      if (e.type === "recoil") {
        lunge(unitEl(e.seat, e.pos), unitEl(e.targetSeat, e.targetPos), 320 / b.speed);
        floater(e.seat, e.pos, "反击", "recoil");
        await wait(180);
      }
      if (e.type === "blocked") floater(e.seat, e.pos, "屏障破碎", "block");
      if (e.type === "switch") { floater(e.seat, e.pos, "转线", "switch"); await wait(300); }
      if (e.type === "note") await wait(600);
    }
    if (!alive()) return;

    // 换成这一帧结束时的样子，再飘数字
    b.snap = f.after;
    render();
    const dmg = new Map<string, number>();
    for (const e of f.events) {
      if (e.type === "damage") dmg.set(`${e.seat}-${e.pos}`, (dmg.get(`${e.seat}-${e.pos}`) ?? 0) + e.amount);
    }
    for (const [k, v] of dmg) {
      const [s, p] = k.split("-").map(Number);
      floater(s as Seat, p, `-${num(Math.round(v * 10) / 10)}`, "dmg");
      unitEl(s as Seat, p)?.classList.add("hit");
    }
    for (const e of f.events) {
      if (e.type === "heal") floater(e.seat, e.pos, `+${num(e.amount)}`, "heal", 250);
      if (e.type === "death") unitEl(e.seat, e.pos)?.classList.add("dying");
    }
    const after = f.events.slice(cut).filter((e): e is Extract<BattleEvent, { type: "trigger" }> => e.type === "trigger");
    await wait(dmg.size ? 650 : 300);
    for (const e of after) {
      if (!alive()) return;
      bubble(e, isOwn(e));
      await wait(500);
    }
    if (f.events.some((e) => e.type === "death")) await wait(400);
  }
  if (!alive()) return;
  b.actor = null;
  b.done = true;
  render();
}

function skipBattle() {
  const b = ui.battle;
  if (!b) return;
  battleToken++;
  b.snap = b.result.final;
  b.round = b.result.rounds;
  b.actor = null;
  const last = b.result.frames.at(-1);
  b.caption = [`第 ${b.round} 轮`, ...(last ? frameCaption(b, last.events) : [])];
  b.done = true;
  render();
}

function closeBattle() {
  battleToken++;
  ui.battle = null;
  render();
  scheduleAi();
}

// ───────────────────────── 卡牌 ─────────────────────────

interface Body {
  atk: number;
  hp: number;
  startHp: number;
  shape: AttackShape;
  armor: number;
  barrier: number;
}

/** 卡面数值：人物面板 + 装备（和战斗引擎的装备结算一致）。开战时的能力加成要等战斗里才看得到。 */
function bodyOf(id: string, equip: string | null): Body {
  const c = character(id);
  const b: Body = { atk: c.atk, hp: c.hp, startHp: c.hp, shape: c.shape, armor: c.armor, barrier: c.barrier };
  if (equip) {
    const e = equipment(equip).effect;
    switch (e.kind) {
      case "stat": b.atk += e.atk; b.hp += e.hp; break;
      case "shape": b.shape = e.shape; b.atk += e.atk; break;
      case "armor": b.armor += e.armor; b.hp += e.hp; break;
      case "barrier": b.barrier = Math.min(2, b.barrier + e.barrier); b.atk += e.atk; break;
    }
    b.startHp = b.hp;
  }
  return b;
}

interface CardOpts {
  equip?: string | null;
  /** 战斗中身上的全部装备（夺装者可能让一人带两件）；给了就不看 equip。 */
  equipList?: string[];
  body?: Body;
  dead?: boolean;
  flag?: string;
  cls?: string;
  act?: string;
  arg?: string | number;
  unit?: string;
}

function attrs(o: { act?: string; arg?: string | number }) {
  return o.act ? ` data-act="${o.act}"${o.arg !== undefined ? ` data-arg="${o.arg}"` : ""} role="button" tabindex="0"` : "";
}

function card(id: string, o: CardOpts = {}) {
  const c = character(id);
  const equip = o.equip ?? null;
  const b = o.body ?? bodyOf(id, equip);
  const atkCls = b.atk > c.atk ? "up" : b.atk < c.atk ? "down" : "";
  const hpCls = b.hp < b.startHp ? "hurt" : b.hp > c.hp ? "up" : "";
  const eqs = (o.equipList ?? (equip ? [equip] : [])).map((x) => equipment(x));
  return `<div class="card ${o.cls ?? ""} ${o.dead ? "dead" : ""} ${o.act ? "clickable" : ""} ${b.barrier ? "shielded" : ""}"
      style="--sin:${SIN_COLOR[c.sin]}"${o.unit ? ` data-unit="${o.unit}"` : ""}${attrs(o)} title="${esc(`${c.name}（${c.sin}）：${c.ability}`)}">
    <div class="art ${ART.has(id) ? "has-portrait" : ""}"><span class="glyph">${SIN_GLYPH[c.sin]}</span>${ART.has(id) ? `<img class="portrait" src="art/${id}.webp" alt="" draggable="false">` : ""}</div>
    <div class="ribbon">${c.name}</div>
    <div class="text">${CARD_TEXT[id] ?? esc(c.ability)}</div>
    ${eqs.length ? `<div class="equip" title="${esc(eqs.map((e) => `${e.name}：${e.text}`).join("；"))}">⚙ ${eqs.map((e) => e.name).join("、")}</div>` : ""}
    <span class="shape-badge ${b.shape}" title="${shapeName(b.shape)}">${shapeName(b.shape)}</span>
    ${b.armor ? `<span class="armor-badge" title="护甲 ${b.armor}">${b.armor}</span>` : ""}
    ${b.barrier ? `<span class="barrier-badge" title="屏障 ${b.barrier}">${b.barrier}</span>` : ""}
    <span class="gem atk ${atkCls}">${num(b.atk)}</span>
    <span class="gem hp ${hpCls}">${num(Math.max(0, b.hp))}</span>
    ${o.flag ? `<span class="flag">${o.flag}</span>` : ""}
    ${o.dead ? `<span class="dead-mark">倒下</span>` : ""}
    <button class="info-btn" data-act="inspect" data-arg="${id}|${equip ?? ""}" aria-label="查看${c.name}">?</button>
  </div>`;
}

function back(o: CardOpts & { text?: string } = {}) {
  const eq = o.equip ? equipment(o.equip) : null;
  return `<div class="card back ${o.cls ?? ""} ${o.act ? "clickable" : ""}"${o.unit ? ` data-unit="${o.unit}"` : ""}${attrs(o)}>
    <div class="emblem">罪</div>
    ${o.text ? `<div class="back-text">${o.text}</div>` : ""}
    ${eq ? `<div class="equip" title="${esc(`${eq.name}：${eq.text}`)}">⚙ ${eq.name}</div>` : ""}
  </div>`;
}

function slot(text: string, o: CardOpts = {}) {
  return `<div class="card slot ${o.cls ?? ""} ${o.act ? "clickable" : ""}"${o.unit ? ` data-unit="${o.unit}"` : ""}${attrs(o)}><span>${text}</span></div>`;
}

function btn(label: string, act: string, arg?: string | number, cls = "") {
  return `<button data-act="${act}"${arg !== undefined ? ` data-arg="${arg}"` : ""} class="${cls}">${label}</button>`;
}

// ───────────────────────── 画面 ─────────────────────────

function render() {
  if (!table) {
    app.innerHTML = sheetView();
    return;
  }
  const o = observe(table, HUMAN);
  app.innerHTML = `
    ${topBar(o)}
    <section class="table">
      ${seatBar(o, AI)}
      <div class="row foe">${ui.battle ? battleRow(ui.battle, AI) : foeRow(o)}</div>
      ${center(o)}
      <div class="row me">${ui.battle ? battleRow(ui.battle, HUMAN) : myRow(o)}</div>
      ${seatBar(o, HUMAN)}
    </section>
    <section class="dock">${ui.error ? `<div class="error">${esc(ui.error)}</div>` : ""}${ui.battle ? battleDock(ui.battle) : dock(o)}</section>
    ${sheetView()}
  `;
  fitTable();
}

/** 牌桌放不下时把卡缩小一点，保证一屏装下、不用滚动。 */
function fitTable() {
  const tb = app.querySelector<HTMLElement>(".table");
  if (!tb) return;
  let f = 1;
  app.style.setProperty("--fit", "1");
  while (f > 0.6 && tb.scrollHeight > tb.clientHeight + 1) {
    f -= 0.05;
    app.style.setProperty("--fit", f.toFixed(2));
  }
}

/** 战斗动画播放时，筹码还停在结算之前，免得提前看出胜负。 */
function shownMoney(o: Observation): { stacks: [number, number]; pot: number } {
  const out = table!.hand.outcome;
  if (!ui.battle || !out || out.by !== "battle") return { stacks: o.stacks, pot: o.pot };
  const stacks: [number, number] = [o.stacks[0], o.stacks[1]];
  if (out.winner === null) {
    stacks[0] -= o.invested[0];
    stacks[1] -= o.invested[1];
  } else {
    stacks[out.winner] -= out.pot;
  }
  return { stacks, pot: out.pot };
}

function topBar(o: Observation) {
  return `<header class="top">
    <div class="brand">七罪暗队<small>v0.3 试玩</small></div>
    <div class="hand-no">第 ${o.handNo} 手 · 底注 ${o.ante}${o.handNo % 5 === 0 ? " · 下手升盲" : ""}</div>
    <nav>${btn("记录", "sheet", "log")}${btn("牌池", "sheet", "pool")}${btn("规则", "sheet", "help")}${btn("新桌", "sheet", "intro")}</nav>
  </header>`;
}

function chipStack(n: number) {
  const k = n <= 0 ? 0 : n < 20 ? 1 : n < 60 ? 2 : 3;
  return `<span class="chips c${k}"><i></i><i></i><i></i></span>`;
}

function seatBar(o: Observation, seat: Seat) {
  const acting = !ui.battle && o.phase !== "over" && o.toAct.includes(seat);
  const name = seat === HUMAN ? "你" : `电脑 · ${STYLE_NAME[style]}`;
  const roundBet = o.phase === "bet" ? o.betting.roundBet[seat] : 0;
  const stack = shownMoney(o).stacks[seat];
  const extra = seat === AI
    ? `<span class="meta">牌池 ${o.opponent.poolSize}${o.opponent.publicPicks.length ? ` · 挑入 ${o.opponent.publicPicks.length}` : ""}</span>`
    : `<span class="meta">牌池 ${o.me.pool.length}</span>`;
  const submitted = seat === AI && o.opponent.submitted && ["operate", "draft", "vote", "bid", "marketRemove"].includes(o.phase);
  return `<div class="seat ${seat === AI ? "top" : "bottom"} ${acting ? "acting" : ""}">
    <span class="avatar">${seat === HUMAN ? "你" : "机"}</span>
    <span class="who">${name}</span>
    ${o.dealer === seat ? `<span class="dealer" title="庄家">庄</span>` : ""}
    <span class="stack">${chipStack(stack)}<b>${stack}</b></span>
    ${extra}
    <span class="status">${acting ? (seat === HUMAN ? "轮到你" : "思考中…") : submitted ? "已决定" : ""}</span>
    ${roundBet ? `<span class="bet-pill">${chipStack(roundBet)}${roundBet}</span>` : ""}
  </div>`;
}

function center(o: Observation) {
  const tile = (which: "arena" | "rule" | "pe", title: string, name: string | null, text: string, state = "") =>
    `<div class="env ${name ? "" : "down"} ${state}" data-act="sheet" data-arg="env:${which}" role="button" tabindex="0">
      <span class="env-title">${title}</span><span class="env-name">${name ?? "未翻开"}</span><span class="env-text">${text}</span></div>`;
  const a = o.arenaId ? arena(o.arenaId) : null;
  const r = o.ruleId ? rule(o.ruleId) : null;
  const pe = o.publicEffectId ? publicEffect(o.publicEffectId) : null;
  const peState = o.publicEffectActive === null ? (pe ? "voting" : "") : o.publicEffectActive ? "on" : "off";
  const peLabel = pe ? `${pe.name}${o.publicEffectActive === null ? "" : o.publicEffectActive ? " ✓" : " ✗"}` : null;
  const tiles = tile("arena", "场地", a?.name ?? null, a?.text ?? `候选：${o.arenaOptions.map((x) => arena(x).name).join(" / ")}`) +
    tile("rule", "胜利规则", r ? r.name : null, r ? `${r.text}（最多 ${r.maxRounds} 轮）` : "第 1 轮下注后翻开") +
    tile("pe", "公共效果", peLabel, pe ? pe.text : r ? "已全押，本手没有" : "和规则一起翻开", peState);
  let status = phaseLabel(o);
  if (ui.battle) {
    const b = ui.battle;
    status = b.round === 0 ? "揭开队伍" : `战斗 · 第 ${b.round} 轮 / 最多 ${rule(b.ruleId).maxRounds} 轮 · ${firstOf(b, b.round) === HUMAN ? "你" : "对手"}先手`;
  }
  return `<div class="center">
    <div class="envs">${tiles}</div>
    <div class="pot-line">
      <div class="pot">${chipStack(shownMoney(o).pot)}<b>${shownMoney(o).pot}</b><small>奖池</small></div>
      ${ui.notice && !ui.battle ? `<div class="notice ${ui.notice.good === true ? "good" : ui.notice.good === false ? "bad" : ""}">${ui.notice.text}</div>` : `<div class="phase">${status}</div>`}
    </div>
  </div>`;
}

function phaseLabel(o: Observation): string {
  switch (o.phase) {
    case "arena": return "选场地";
    case "place": return "排位";
    case "peek": return "窥视";
    case "bet": return `第 ${o.betting.round} 轮下注`;
    case "operate": return "操作：拿装备？";
    case "draft": return "挑装备";
    case "vote": return "公共效果表决";
    case "bid": return "暗标";
    case "marketPick": return "市场";
    case "marketRemove": return "整理牌池";
    case "over": return "牌桌结束";
  }
}

function foeRow(o: Observation): string {
  const opp = o.opponent;
  const lb = ui.lastBattle && ui.lastBattle.hand === o.handNo ? ui.lastBattle : null;
  if (lb) return battleUnits(lb.result.final[AI], lb.teams[AI].reveal);
  const peeking = o.phase === "peek" && o.toAct.includes(HUMAN);
  return [0, 1, 2].map((pos) => {
    const eq = opp.equipment[pos];
    const unit = `${AI}-${pos}`;
    if (!opp.placed) return back({ text: o.phase === "arena" ? "" : "排位中…", unit });
    if (opp.emptyPositions.includes(pos)) return slot("空位<br><small>被饕餮吞掉</small>", { unit });
    if (opp.revealed?.pos === pos) return card(opp.revealed.characterId, { equip: eq, flag: "亮", unit });
    if (o.me.peek?.pos === pos) return card(o.me.peek.characterId, { equip: eq, flag: "偷看", unit });
    if (peeking) return back({ equip: eq, text: "点这里偷看", act: "peek", arg: pos, cls: "target", unit });
    return back({ equip: eq, unit });
  }).join("");
}

function myRow(o: Observation): string {
  const lb = ui.lastBattle && ui.lastBattle.hand === o.handNo ? ui.lastBattle : null;
  if (lb) return battleUnits(lb.result.final[HUMAN], lb.teams[HUMAN].reveal);
  const placing = o.phase === "place" && o.toAct.includes(HUMAN);
  if (placing) {
    const dealt = o.me.dealt;
    return [0, 1, 2].map((pos) => {
      const i = ui.place.slots[pos];
      if (i === null) return slot(posName(pos));
      if (ui.place.eaten === pos) return slot(`被饕餮吞掉<br><small>${character(dealt[i]).name}</small>`, { act: "eat", arg: -1 });
      const rev = ui.place.reveal === pos;
      return card(dealt[i], { flag: rev ? "亮" : "暗", act: "reveal", arg: pos, cls: rev ? "selected" : "target" });
    }).join("");
  }
  const pl = o.me.placement;
  if (!pl) return [0, 1, 2].map((pos) => slot(posName(pos))).join("");
  const drafting = o.phase === "draft" && !!o.me.offers && o.toAct.includes(HUMAN) && ui.draft.offer !== null;
  return pl.slots.map((id, pos) => {
    if (!id) return slot("空位<br><small>被吞掉</small>");
    let equip = o.me.equipment[pos];
    let cls = "";
    if (drafting) {
      cls = ui.draft.pos === pos ? "selected" : "target";
      if (ui.draft.pos === pos) equip = o.me.offers![ui.draft.offer!];
    }
    return card(id, {
      equip, flag: pos === pl.reveal ? "亮" : "暗", cls,
      act: drafting ? "draftPos" : undefined, arg: pos,
    });
  }).join("");
}

function battleUnits(snaps: UnitSnapshot[], reveal: number) {
  return snaps.map((u) => {
    const key = `${u.seat}-${u.pos}`;
    if (!u.characterId) return slot("空位", { unit: key });
    const body: Body = { atk: u.atk, hp: u.hp, startHp: u.startHp, shape: u.shape, armor: u.armor, barrier: u.barrier };
    return card(u.characterId, { equipList: u.equipment, body, dead: !u.alive, unit: key, flag: u.pos === reveal ? "亮" : undefined });
  }).join("");
}

function battleRow(b: Playback, seat: Seat) {
  let html = battleUnits(b.snap[seat], b.teams[seat].reveal);
  if (b.actor) html = html.replace(`data-unit="${b.actor}"`, `data-unit="${b.actor}" data-acting="1"`);
  if (seat === AI && b.caption[0] === "揭开双方队伍") {
    html = html.replaceAll('class="card ', 'class="card flip-in ');
  }
  return html;
  return html;
}

// ───────────────────────── 操作栏 ─────────────────────────

function prompt(text: string, sub = "") {
  return `<div class="prompt">${text}${sub ? `<small>${sub}</small>` : ""}</div>`;
}

function waiting(text: string) {
  return `<div class="prompt waiting">${text}<span class="dots"><i></i><i></i><i></i></span></div>`;
}

function dock(o: Observation): string {
  const mine = o.toAct.includes(HUMAN);
  switch (o.phase) {
    case "over": {
      const won = table!.winner === HUMAN;
      return `<div class="result ${won ? "good" : "bad"}">${won ? "你赢下了这张牌桌！" : "对手赢下了这张牌桌"}<small>共 ${table!.handNo} 手</small></div>
        <div class="actions">${btn("再开一桌", "sheet", "intro", "primary big")}</div>`;
    }
    case "arena": return arenaDock(o, mine);
    case "place": return placeDock(o, mine);
    case "peek": return mine ? prompt("你的窥视者可以偷看一张暗牌", "点对手的一张暗牌") : waiting("对手的窥视者在偷看你的暗牌");
    case "bet": return mine ? betDock(o) : waiting(`对手在考虑第 ${o.betting.round} 轮下注`);
    case "operate": return mine ? operateDock(o) : waiting("等对手决定要不要拿装备");
    case "draft": return mine && o.me.offers ? draftDock(o) : waiting("对手在挑装备");
    case "vote": return mine ? voteDock(o) : waiting("等对手表决");
    case "bid": return mine ? bidDock(o) : waiting("等对手暗标出价");
    case "marketPick": return marketDock(o, mine);
    case "marketRemove": return mine ? removeDock(o) : waiting("等对手整理牌池");
  }
}

function arenaDock(o: Observation, mine: boolean) {
  const tiles = o.arenaOptions.map((id, i) => {
    const a = arena(id);
    return `<div class="option ${mine ? "clickable" : ""}"${mine ? attrs({ act: "arena", arg: i }) : ""}><b>${a.name}</b><small>${a.kind}</small><p>${a.text}</p></div>`;
  }).join("");
  return (mine ? prompt("选一张场地", "你筹码较少（或一样多且你不是庄家）") : waiting("对手在选场地")) + `<div class="tray options">${tiles}</div>`;
}

function placeDock(o: Observation, mine: boolean) {
  const dealt = o.me.dealt;
  const tray = (clickable: boolean) => `<div class="tray hand">${dealt.map((id, i) => {
    const at = ui.place.slots.indexOf(i);
    return card(id, {
      cls: `small ${clickable && at >= 0 ? "used" : ""}`, flag: clickable && at >= 0 ? posName(at) : undefined,
      act: clickable ? "pick" : undefined, arg: i,
    });
  }).join("")}</div>`;
  if (!mine) {
    return waiting(o.dealer === HUMAN ? "对手先排位、先亮牌" : "对手是庄家，看过你亮的牌再排") + tray(false);
  }
  const filled = ui.place.slots.every((x) => x !== null);
  const ids = ui.place.slots.map((i) => (i === null ? null : dealt[i]));
  const gl2 = ids.indexOf("GL2");
  let ok = false;
  let why = "";
  if (!filled) why = "点下面的牌依次放到 1、2、3 号位（再点一次取回）";
  else if (ui.place.reveal === null) why = "点上面你的一张牌，把它设为亮出";
  else {
    try {
      validatePlacement(dealt, ui.place.slots as number[], ui.place.eaten !== null ? { eater: gl2, eaten: ui.place.eaten } : null, ui.place.reveal);
      ok = true;
    } catch (err) {
      why = err instanceof Error ? err.message : String(err);
    }
  }
  const head = ok
    ? prompt(`亮出 ${posName(ui.place.reveal!)} ${character(ids[ui.place.reveal!]!).name}`, "点上面的牌可以换一名亮出")
    : prompt(o.dealer === HUMAN ? "你是庄家，后排位" : "你先排位：对手会看到你亮的那一名", why);
  let eat = "";
  if (gl2 >= 0 && filled) {
    eat = `<div class="actions compact"><span class="label">饕餮吞队友：</span>${btn("不吞", "eat", -1, ui.place.eaten === null ? "on" : "")}
      ${[0, 1, 2].filter((p) => p !== gl2).map((p) => btn(`${posName(p)} ${character(ids[p]!).name}`, "eat", p, ui.place.eaten === p ? "on" : "")).join("")}</div>`;
  }
  return head + tray(true) + eat + `<div class="actions">
    ${btn("清空", "clearPlace", undefined, ui.place.slots.some((x) => x !== null) ? "big" : "big disabled")}
    ${btn("确认排位", "place", undefined, `primary big ${ok ? "" : "disabled"}`)}</div>`;
}

function betDock(o: Observation) {
  const b = o.betting;
  const stack = o.stacks[HUMAN];
  const me = b.roundBet[HUMAN];
  const acts = legalActions(table!, HUMAN);
  const has = (t: Action["type"]) => acts.some((a) => a.type === t);
  const opening = b.target === 0;
  const min = opening ? table!.options.minBet : b.minRaiseTo;
  const max = opening ? stack - 1 : me + stack - 1;
  const canSize = min <= max;
  if (canSize && (ui.betAmount === null || ui.betAmount < min || ui.betAmount > max)) ui.betAmount = min;
  const quick = acts.flatMap((a) => (a.type === "bet" ? [a.amount] : a.type === "raise" ? [a.to] : []));
  const verb = opening ? "下注" : "加注到";
  const toCall = Math.min(b.toCall, stack);
  const sub = b.canFold ? "" : "对手亮出了冠冕者：第 1 轮不能弃牌";
  return prompt(toCall ? `对手下注，你要跟 ${toCall}` : `第 ${b.round} 轮下注`, sub) +
    (canSize ? `<div class="sizer">
      ${quick.map((x) => btn(String(x), "setBet", x, `chip-btn ${x === ui.betAmount ? "on" : ""}`)).join("")}
      <input type="range" min="${min}" max="${max}" step="1" value="${ui.betAmount}" data-input="bet" aria-label="金额">
      <input type="number" min="${min}" max="${max}" step="1" value="${ui.betAmount}" data-input="bet" aria-label="金额">
    </div>` : "") +
    `<div class="actions poker">
      ${has("fold") ? btn("弃牌", "fold", undefined, "fold big") : ""}
      ${has("check") ? btn("过牌", "check", undefined, "call big") : ""}
      ${has("call") ? btn(`跟注 ${toCall}`, "call", undefined, "call big") : ""}
      ${canSize ? btn(`${verb} <b data-bind="bet">${ui.betAmount}</b>`, "betSized", undefined, "raise big") : ""}
      ${has("allIn") ? btn(`全押 ${stack}`, "allIn", undefined, "allin big") : ""}
    </div>`;
}

function operateDock(o: Observation) {
  return prompt(`付 ${o.opFee} 操作费，从 3 件装备里挑 1 件？`, "装备装在谁身上对手看得到") +
    `<div class="actions">${btn("不拿", "operate", 0, "big")}${btn(`付 ${o.opFee} 拿装备`, "operate", 1, "primary big")}</div>`;
}

function draftDock(o: Observation) {
  const offers = o.me.offers!;
  const tiles = offers.map((id, i) => {
    const e = equipment(id);
    return `<div class="option clickable ${ui.draft.offer === i ? "selected" : ""}"${attrs({ act: "draftOffer", arg: i })}><b>⚙ ${e.name}</b><p>${e.text}</p></div>`;
  }).join("");
  const ready = ui.draft.offer !== null && ui.draft.pos !== null;
  const sub = ui.draft.offer === null ? "先选一件" : ui.draft.pos === null ? "再点上面你的一张牌，装给它" : `装到 ${posName(ui.draft.pos)}`;
  return prompt("挑一件装备", sub) + `<div class="tray options three">${tiles}</div>
    <div class="actions">${btn("确认装备", "draft", undefined, `primary big ${ready ? "" : "disabled"}`)}</div>`;
}

function voteDock(o: Observation) {
  const pe = publicEffect(o.publicEffectId!);
  return prompt(`公共效果「${pe.name}」要不要生效？`, `${pe.text}。双方暗投；不一致就暗标。`) +
    `<div class="actions">${btn("不生效", "vote", 0, "big")}${btn("生效", "vote", 1, "primary big")}</div>`;
}

function bidDock(o: Observation) {
  const cap = o.bidCap;
  if (ui.bid > cap) ui.bid = cap;
  const quick = [...new Set([0, 5, 10, 20, Math.floor(cap / 2), cap].filter((x) => x <= cap))].sort((a, b) => a - b);
  return prompt(`暗标：你投了${o.me.vote ? "生效" : "不生效"}，对手相反`, `出价高的一方说了算，只付自己的出价；一样多则不生效。最多 ${cap}`) +
    `<div class="sizer">
      ${quick.map((x) => btn(String(x), "setBid", x, `chip-btn ${x === ui.bid ? "on" : ""}`)).join("")}
      <input type="range" min="0" max="${cap}" step="1" value="${ui.bid}" data-input="bid" aria-label="出价">
      <input type="number" min="0" max="${cap}" step="1" value="${ui.bid}" data-input="bid" aria-label="出价">
    </div>
    <div class="actions">${btn(`出价 <b data-bind="bid">${ui.bid}</b>`, "bid", undefined, "primary big")}</div>`;
}

function marketDock(o: Observation, mine: boolean) {
  const stage = Table.marketStageFor(o.handNo, table!.options.blindEvery);
  const tray = `<div class="tray hand">${o.market.map((id, i) => card(id, { cls: "small", act: mine ? "marketPick" : undefined, arg: i })).join("")}</div>`;
  return (mine ? prompt("市场：挑一名放进你的牌池", `本手输家先挑，挑了谁对手看得到 · 市场阶段 ${stage}`) : waiting("对手在市场挑人")) + tray;
}

function removeDock(o: Observation) {
  const pool = o.me.pool;
  const min = table!.options.minPoolSize;
  const canRemove = pool.length - 1 >= min;
  const sel = ui.removeIdx;
  return prompt("要从牌池移除一名吗？", canRemove ? `对手看不到你移除了谁 · 牌池至少留 ${min} 名` : `牌池已经只剩 ${min} 名，不能再移除`) +
    (canRemove ? `<div class="tray hand scroll">${pool.map((id, i) => card(id, { cls: `small ${sel === i ? "selected" : ""}`, act: "pickRemove", arg: i })).join("")}</div>` : "") +
    `<div class="actions">${btn("不移除", "remove", -1, sel === null ? "primary big" : "big")}
      ${sel !== null ? btn(`移除 ${character(pool[sel]).name}`, "remove", sel, "fold big") : ""}</div>`;
}

function battleDock(b: Playback) {
  const r = b.result;
  const lines = b.caption;
  const cap = `<div class="caption"><b>${lines[0]}</b>${lines.slice(1).map((l) => `<span>${esc(l)}</span>`).join("")}</div>`;
  if (b.done) {
    const cls = r.winner === HUMAN ? "good" : r.winner === null ? "" : "bad";
    const text = r.winner === null ? "平局" : r.winner === HUMAN ? "你赢了这场战斗" : "对手赢了这场战斗";
    return cap + `<div class="result ${cls}">${text}<small>${REASON_TEXT[r.reason]} · 规则「${rule(b.ruleId).name}」</small></div>
      <div class="actions">${btn("继续", "bClose", undefined, "primary big")}</div>`;
  }
  return cap + `<div class="actions">
    ${btn(b.paused ? "▶ 继续" : "❚❚ 暂停", "bPause", undefined, "big")}
    ${btn(b.speed === 1 ? "加速 ×2" : "正常速度", "bSpeed", undefined, "big")}
    ${btn("跳到结果", "bSkip", undefined, "big")}</div>`;
}

// ───────────────────────── 弹层 ─────────────────────────

function sheetView(): string {
  const s = ui.sheet;
  if (!s) return "";
  const wrap = (cls: string, inner: string, closable = true) =>
    `<div class="overlay" ${closable ? `data-act="closeSheet"` : ""}><div class="sheet ${cls}" data-stop="1" role="dialog">
      ${closable ? `<button class="close" data-act="closeSheet" aria-label="关闭">×</button>` : ""}${inner}</div></div>`;
  switch (s.kind) {
    case "intro":
      return wrap("intro", `<div class="intro-art">罪</div>
        <h2>七罪暗队<small>v0.3 试玩</small></h2>
        <p>德州扑克的下注 + 酒馆战棋的身材和自动战斗。每手从牌池排出 3 名人物、只亮 1 名，靠下注讲故事，揭开后自动开打。</p>
        <p>你和电脑各 100 筹码，赢光对方就赢下牌桌。</p>
        <div class="label">选择电脑对手</div>
        <div class="actions">${btn("谨慎", "start", "cautious", "primary big")}${btn("激进", "start", "aggressive", "big")}${btn("爱诈唬", "start", "bluff", "big")}</div>
        <div class="actions">${btn("先看规则", "sheet", "help")}</div>`, !!table);
    case "help": {
      const tabs: Array<[Ui["helpTab"], string]> = [["play", "玩法"], ["chars", "人物"], ["equip", "装备"], ["rules", "胜利规则"], ["arenas", "场地"], ["effects", "公共效果"]];
      let body = "";
      switch (ui.helpTab) {
        case "play": body = HOW_TO_PLAY; break;
        case "chars": body = `<p class="muted">开桌时每人的牌池从全部人物里随机 8 名。市场里，第 1–5 手只出第一阶段人物，第 6 手起只出标“二”的人物。点卡上的 ? 看能力。</p>
          <div class="gallery">${CHARACTERS.map((c) => card(c.id, { cls: "small", flag: c.stage === 2 ? "二" : undefined })).join("")}</div>`; break;
        case "equip": body = refTable(EQUIPMENT.map((e) => [e.name, e.text])); break;
        case "rules": body = refTable(RULES.map((r) => [`${r.name}<small>${r.family} · 最多 ${r.maxRounds} 轮</small>`, r.text])); break;
        case "arenas": body = refTable(ARENAS.map((a) => [`${a.name}<small>${a.kind}</small>`, a.text])); break;
        case "effects": body = refTable(PUBLIC_EFFECTS.map((p) => [`${p.name}<small>${p.kind}</small>`, p.text])); break;
      }
      return wrap("help", `<div class="tabs">${tabs.map(([k, l]) => btn(l, "tab", k, ui.helpTab === k ? "on" : "")).join("")}</div>
        <div class="sheet-body">${body}</div>`);
    }
    case "card": {
      const c = character(s.id);
      const eq = s.equip ? equipment(s.equip) : null;
      return wrap("card-sheet", `${ART.has(s.id) ? `<img class="full-portrait" src="art/${s.id}.webp" alt="${c.name}立绘">` : ""}<div class="big-card">${card(s.id, { equip: s.equip, cls: "large" })}</div>
        <div class="card-info"><h2>${c.name}<small>${c.sin} · ${c.tag}${c.stage === 2 ? " · 第二阶段" : ""}</small></h2>
        <p class="stats">攻 <b>${c.atk}</b> · 血 <b>${c.hp}</b> · ${shapeName(c.shape)}${c.armor ? ` · 护甲 ${c.armor}` : ""}${c.barrier ? ` · 屏障 ${c.barrier}` : ""}</p>
        <p class="ability">${esc(c.ability)}</p>
        ${eq ? `<p class="equip-line">⚙ ${eq.name}：${eq.text}</p>` : ""}
        <p class="muted">重击 → 护甲 → 连击 → 屏障 → 重击：前者克后者。</p></div>`);
    }
    case "env": {
      const o = observe(table!, HUMAN);
      let title = "";
      let body = "";
      if (s.which === "arena") {
        title = "场地";
        body = o.arenaId ? `<h2>${arena(o.arenaId).name}</h2><p>${arena(o.arenaId).text}</p>`
          : o.arenaOptions.map((id) => `<h3>${arena(id).name}</h3><p>${arena(id).text}</p>`).join("");
      } else if (s.which === "rule") {
        title = "胜利规则";
        const r = o.ruleId ? rule(o.ruleId) : null;
        body = r ? `<h2>${r.name}<small>${r.family} · 最多 ${r.maxRounds} 轮</small></h2><p>${r.text}</p>` : "<p>第 1 轮下注结束后翻开。</p>";
      } else {
        title = "公共效果";
        const pe = o.publicEffectId ? publicEffect(o.publicEffectId) : null;
        body = pe ? `<h2>${pe.name}<small>${o.publicEffectActive === null ? "表决中" : o.publicEffectActive ? "生效" : "不生效"}</small></h2><p>${pe.text}</p>`
          : "<p>和胜利规则一起翻开。双方暗投要不要生效，不一致就暗标。</p>";
      }
      return wrap("env-sheet", `<div class="label">${title}</div>${body}`);
    }
    case "log": {
      const lines = logLines.slice(-120).reverse();
      return wrap("drawer", `<h2>牌桌记录</h2><ol class="log">${lines.map((l) => `<li class="${l.startsWith("——") ? "sep" : ""}">${esc(l)}</li>`).join("")}</ol>`);
    }
    case "pool": {
      const o = observe(table!, HUMAN);
      const picks = o.opponent.publicPicks;
      return wrap("drawer", `<h2>我的牌池<small>${o.me.pool.length} 名 · 每手从这里随机发 4 名</small></h2>
        <div class="gallery">${o.me.pool.map((id) => card(id, { cls: "small" })).join("")}</div>
        <h2>对手<small>牌池 ${o.opponent.poolSize} 名${o.opponent.removedCount ? ` · 移除过 ${o.opponent.removedCount} 名` : ""}</small></h2>
        ${picks.length ? `<p class="muted">从市场公开挑入：</p><div class="gallery">${picks.map((id) => card(id, { cls: "small" })).join("")}</div>` : `<p class="muted">还没从市场挑过人；其余都是未知的。</p>`}`);
    }
  }
}

function refTable(rows: Array<[string, string]>) {
  return `<table class="ref">${rows.map(([a, b]) => `<tr><th>${a}</th><td>${b}</td></tr>`).join("")}</table>`;
}

// ───────────────────────── 输入 ─────────────────────────

function onAct(name: string, arg: string | undefined) {
  const n = arg === undefined ? NaN : Number(arg);
  const o = table && table.phase !== "over" ? observe(table, HUMAN) : null;
  switch (name) {
    case "sheet": {
      if (arg?.startsWith("env:")) ui.sheet = { kind: "env", which: arg.slice(4) as "arena" | "rule" | "pe" };
      else ui.sheet = { kind: arg as "intro" | "help" | "log" | "pool" };
      return render();
    }
    case "closeSheet": ui.sheet = table ? null : { kind: "intro" }; render(); return scheduleAi();
    case "inspect": {
      const [id, eq] = (arg ?? "").split("|");
      ui.sheet = { kind: "card", id, equip: eq || null };
      return render();
    }
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
        if (free < 0) { ui.error = "3 个位置都排满了，先点一张已排的牌取回"; return render(); }
        ui.place.slots[free] = n;
      }
      ui.place.eaten = null;
      ui.error = null;
      return render();
    }
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
    case "pickRemove": ui.removeIdx = ui.removeIdx === n ? null : n; return render();
    case "remove": return act({ type: "marketRemove", poolIndex: n < 0 ? null : n });
    case "bPause": if (ui.battle) ui.battle.paused = !ui.battle.paused; return render();
    case "bSpeed": if (ui.battle) ui.battle.speed = ui.battle.speed === 1 ? 2 : 1; return render();
    case "bSkip": return skipBattle();
    case "bClose": return closeBattle();
  }
}

app.addEventListener("click", (ev) => {
  const target = ev.target as HTMLElement;
  const el = target.closest<HTMLElement>("[data-act]");
  if (!el || el.classList.contains("disabled")) return;
  // 点弹层内容本身不关闭弹层
  if (el.classList.contains("overlay") && target.closest("[data-stop]")) return;
  onAct(el.dataset.act!, el.dataset.arg);
});

app.addEventListener("keydown", (ev) => {
  if (ev.key === "Escape" && ui.sheet && table) return onAct("closeSheet", undefined);
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
  app.querySelectorAll<HTMLElement>(".chip-btn").forEach((x) => x.classList.toggle("on", Number(x.dataset.arg) === v));
});

window.addEventListener("resize", () => render());
render();

// 给自动化测试用：读当前牌桌（不影响游戏）
(window as unknown as { __sinSquad: unknown }).__sinSquad = {
  get table() { return table; },
  get ui() { return ui; },
};
