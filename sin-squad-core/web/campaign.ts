import type { CampaignProgress } from "../src/campaign/progress.js";
import { MIN_CAMPAIGN_POOL, STAGES, stage, type StageDef } from "../src/campaign/stages.js";
import { arena, rule } from "../src/content/tables.js";
import { SIN_LATIN } from "./sigil.js";
import { SIN_COLOR, esc } from "./text.js";

/**
 * 炼狱战役的几屏（画在入场那一层 #gate 里）：18+ 确认、炼狱之馆、关前、一关打完、挑人。
 * 这里只生成 HTML；点击统一走 data-go，由 intro.ts 的 Gate 处理。
 *
 * 画面语言跟牌桌一样是哥特教堂：
 * - 炼狱之馆是一座七层的塔，每层一扇玫瑰窗（设计稿 §4.1：每赢一位，亮一扇），塔底是人间的酒馆门；
 * - 关前、结算像视觉小说：她的主场插画铺满背景，立绘（没画的先用她那一罪颜色的玫瑰窗）站在左边，
 *   底下是带名牌的对话框；专属规则、主场做成和桌上一样的珐琅金属牌；
 * - 挑人沿用牌桌上“发现”的样子：候选浮在正中，挑中的发金光。
 */

/** 正在进行、还没打完的那一关（存档里的）。 */
export interface StageSave { stage: number; handNo: number; stacks: [number, number] }

/** 一关刚打完的结果。 */
export interface StageResult {
  stage: number;
  won: boolean;
  /** 输了：她这次的嘲讽。 */
  taunt: string | null;
  /** 这一关到现在重来的次数。 */
  retries: number;
  /** 第一次通关（有魔神牌、有挑人）。 */
  firstClear: boolean;
}

export interface CampaignCtx {
  progress: CampaignProgress;
  saved: StageSave | null;
  art: Set<string>;
  card(id: string, cls?: string, down?: boolean): string;
}

// ───────── 18+ 确认 ─────────

const ADULT_KEY = "sinsquad.adult.v1";

/** 确认过一次就记在浏览器里，下次不再问。存不了（无痕模式等）就每次都问。 */
export function adultConfirmed(): boolean {
  try { return localStorage.getItem(ADULT_KEY) === "1"; } catch { return false; }
}

export function confirmAdult() {
  try { localStorage.setItem(ADULT_KEY, "1"); } catch { /* 存不了只影响下次 */ }
}

/** 这一屏之前不加载任何立绘和 CG：只有文字和矢量纹章。 */
export function ageView(refused: boolean): string {
  const body = refused
    ? `<p class="age-text">本游戏仅面向年满 18 岁的玩家。</p>
       <div class="gate-actions row"><button data-go="age">返回</button></div>`
    : `<p class="age-text">本游戏包含成人向的角色形象与剧情，<br>仅面向年满 <b>18</b> 岁的玩家。所有角色均为成年人。</p>
       <div class="gate-actions row">
         <button data-go="refuse">未满 18 岁，离开</button>
         <button class="primary big" data-go="adult" autofocus>我已年满 18 岁</button>
       </div>`;
  return `<div class="age-stage">
    <div class="age-seal"><span>XVIII</span></div>
    <div class="logo-latin">SEPTEM · PECCATA · MORTALIA</div>
    <h1 class="logo small">七罪暗队</h1>
    ${body}
  </div>`;
}

// ───────── 小部件 ─────────

export const stageColor = (s: StageDef) => (s.sin ? SIN_COLOR[s.sin] : "#d9a44a");
const stageLatin = (s: StageDef) => (s.sin ? SIN_LATIN[s.sin] : "TABERNA");
const ROMAN = ["", "I", "II", "III", "IV", "V", "VI", "VII"];
const stageLabel = (s: StageDef) => (s.no === 0 ? "序章 · 人间酒馆" : `第 ${ROMAN[s.no]} 层 · ${s.sin}`);

/**
 * 一扇玫瑰窗：七片尖拱花瓣是她那一罪颜色的彩色玻璃，金色窗棂。
 * lit = 已经赢过她（玻璃透光）；dim = 还没解锁（玻璃是灰的）。
 */
function rose(color: string, state: "lit" | "open" | "dim"): string {
  const petal = `M-4.6,-12 Q-6,-22 0,-29.2 Q6,-22 4.6,-12 Q0,-10.4 -4.6,-12Z`;
  const glass = state === "dim" ? "#3a3440" : color;
  const alpha = state === "lit" ? 0.95 : state === "open" ? 0.7 : 0.55;
  const petals = Array.from({ length: 7 }, (_, i) =>
    `<path d='${petal}' transform='rotate(${((i * 360) / 7).toFixed(2)})' fill='${glass}' fill-opacity='${alpha}' stroke='url(#rg)' stroke-width='.9'/>` +
    `<path d='${petal}' transform='rotate(${((i * 360) / 7).toFixed(2)}) scale(.55) translate(0 -9)' fill='#fff' fill-opacity='${state === "dim" ? 0.04 : 0.16}'/>`,
  ).join("");
  const ring = Array.from({ length: 28 }, (_, i) => {
    const a = (i / 28) * Math.PI * 2;
    return `<circle cx='${(33 * Math.cos(a)).toFixed(2)}' cy='${(33 * Math.sin(a)).toFixed(2)}' r='.9'/>`;
  }).join("");
  return `<svg class="rose-svg" viewBox="-40 -40 80 80" aria-hidden="true">
    <defs><linearGradient id="rg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#f6e2a8"/><stop offset=".5" stop-color="#d4ac5a"/><stop offset="1" stop-color="#8a6424"/></linearGradient></defs>
    <circle r="37.5" fill="#12060b" stroke="url(#rg)" stroke-width="1.6"/>
    <circle r="31" fill="none" stroke="url(#rg)" stroke-width=".5"/>
    <g fill="#d4ac5a">${ring}</g>${petals}
    <circle r="9.5" fill="#1a070e" stroke="url(#rg)" stroke-width="1"/>
    <circle r="4" fill="${glass}" fill-opacity="${alpha}" stroke="url(#rg)" stroke-width=".6"/>
  </svg>`;
}

/**
 * 她站在画面上的样子：有立绘用立绘，套一道哥特尖拱金框；
 * 没画的先放一扇她那一罪颜色的大玫瑰窗，底下刻拉丁名。
 */
export function stageFace(s: StageDef, art: Set<string>, cls = ""): string {
  const has = !!s.portrait && art.has(s.portrait);
  return `<div class="sister ${has ? "has-art" : "no-art"} ${cls}" style="--sin:${stageColor(s)}">
    ${has ? `<img src="art/${s.portrait}.webp" alt="${s.foe}" draggable="false">` : `<div class="sister-rose">${rose(stageColor(s), "lit")}</div>`}
    ${has ? "" : `<span class="sister-latin">${stageLatin(s)}</span>`}
  </div>`;
}

/** 关前、结算页的背景：她的主场插画，压暗并染上她的罪色。 */
function scene(s: StageDef, art: Set<string>, inner: string, cls = ""): string {
  const bg = art.has(s.arenaId) ? ` style="--sin:${stageColor(s)};--scene:url('art/${s.arenaId}.webp')"` : ` style="--sin:${stageColor(s)}"`;
  return `<div class="vn ${cls}"${bg}><div class="vn-bg"></div><div class="embers">${"<i></i>".repeat(14)}</div>${inner}</div>`;
}

/** 对话框：带名牌，像视觉小说。 */
function dialog(s: StageDef, line: string, extra = ""): string {
  return `<div class="vn-dialog">
    <div class="vn-name"><b>${s.foe}</b><small>${stageLatin(s)}</small></div>
    <p class="vn-line">${esc(line)}</p>${extra}
  </div>`;
}

/** 和桌上同一家族的珐琅金属牌（切角、铜边、图标）：专属规则宝蓝、主场铜绿。 */
function plate(kind: "rule" | "arena", title: string, name: string, text: string, off = false): string {
  return `<div class="plate p-${kind}${off ? " off" : ""}">
    <span class="plate-icon"></span>
    <span class="plate-text"><small>${title}</small><b>${esc(name)}</b><span>${text}</span></span>
  </div>`;
}

// ───────── 炼狱之馆：一座七层的塔 ─────────

export function campaignView(c: CampaignCtx): string {
  const p = c.progress;
  const lit = Math.max(0, Math.min(7, p.cleared - 1));
  const floors = STAGES.map((s) => {
    const open = s.no <= p.cleared;
    const done = s.no < p.cleared;
    const tries = p.retries[s.no];
    const state = done ? "lit" : open ? "open" : "dim";
    const note = done
      ? `<em class="ok">已通关${p.clearedAfter[s.no] ? ` · 重来 ${p.clearedAfter[s.no]} 次` : ""}</em>`
      : open ? `<em class="now">${tries ? `挑战中 · 输过 ${tries} 次` : "挑战中"}</em>` : `<em>赢下前一层才能上楼</em>`;
    const saved = c.saved?.stage === s.no ? `<em class="saved">牌桌没打完 · 第 ${c.saved.handNo} 手</em>` : "";
    const attrs = open ? `data-go="brief" data-arg="${s.no}" role="button" tabindex="0"` : `aria-disabled="true"`;
    const side = s.no === 0 ? "base" : s.no % 2 ? "left" : "right";
    const win = s.no === 0
      ? `<div class="door">${rose(stageColor(s), state)}</div>`
      : `<div class="window">${rose(stageColor(s), state)}<span class="floor-no">${ROMAN[s.no]}</span></div>`;
    return `<div class="floor ${state} ${side}" style="--sin:${stageColor(s)}" ${attrs}>
      ${win}
      <div class="floor-plate">
        <small>${s.no === 0 ? "PROLOGUS" : `${ROMAN[s.no]} · ${stageLatin(s)}`}</small>
        <b>${open ? s.foe : "？？？"}</b>
        <span class="floor-rule">${open ? `规则「${esc(s.ruleName)}」` : (s.sin ?? "")}</span>
        ${note}${saved}
      </div>
    </div>`;
  }).join("");
  const all = p.cleared >= STAGES.length;
  const demons = STAGES.filter((s) => s.demon).map((s) => {
    const got = p.demons.includes(s.demon!);
    return `<div class="demon ${got ? "got" : ""}" style="--sin:${stageColor(s)}" title="${got ? `魔神牌「${s.demon}」` : "打败她才能得到"}">
      <span>${got ? s.demon : "？"}</span></div>`;
  }).join("");
  return `<div class="tower-stage">
    <button class="gate-back" data-go="back" aria-label="返回">‹ 标题</button>
    <header class="tower-head">
      <div class="logo-latin">PURGATORIUM</div>
      <h1 class="logo small">炼狱之馆</h1>
      <p class="tower-sub">${all ? "七扇玫瑰窗都亮了。门开着，你随时可以回来再打一遍。" : "赢过七姐妹，你才能离开。每一层都打到一方输光筹码；输了可以无限重来。"}</p>
      <div class="tower-count"><b>${lit}</b> / 7 扇玫瑰窗已点亮</div>
    </header>
    <div class="tower"><div class="spire"></div>${floors}</div>
    <footer class="tower-foot">
      <div class="demons"><small>魔神牌</small>${demons}</div>
      <div class="gate-actions row">
        <button data-go="pool">我的牌池 · ${p.pool.length} 名</button>
        ${p.offer ? `<button class="primary big" data-go="reward">挑人<small>打败${stage(p.offer.stage).foe}的奖励还没领</small></button>` : ""}
      </div>
    </footer>
  </div>`;
}

// ───────── 关前 ─────────

export function briefView(c: CampaignCtx, no: number): string {
  const s = stage(no);
  const p = c.progress;
  const tries = p.retries[no];
  const saved = c.saved?.stage === no ? c.saved : null;
  const a = arena(s.arenaId);
  const facts = [
    [`${s.buyIn}`, "各带筹码"],
    s.betting ? [`${s.baseAnte}`, `底注 · 每 ${s.blindEvery} 手翻倍`] : [`${s.baseAnte}`, "每手固定押，不下注"],
    s.betting ? [`${s.deal} 选 3`, "每手发牌"] : ["3 张", "全部上场，只排位置"],
  ].map(([v, k]) => `<div class="fact"><b>${v}</b><small>${k}</small></div>`).join("");
  const warn = [
    no < p.cleared ? "你已经赢过她了：重打不会再给奖励。" : "",
    c.saved && c.saved.stage !== no ? `开这一关会放弃你在「${stage(c.saved.stage).foe}」那一层没打完的牌桌。` : "",
  ].filter(Boolean).map((w) => `<p class="vn-warn">${w}</p>`).join("");
  const inner = `
    <button class="gate-back" data-go="campaign" aria-label="返回">‹ 炼狱之馆</button>
    <div class="vn-cast">${stageFace(s, c.art, "vn-face")}</div>
    <div class="vn-side">
      <div class="vn-kicker">${stageLabel(s)}</div>
      <h2 class="vn-title">${s.foe}</h2>
      <p class="vn-about">${esc(s.title)}</p>
      <div class="plates">
        ${plate("rule", "专属规则", s.ruleName, esc(s.ruleText))}
        ${plate("arena", "主场", a.name, s.arenaActive ? esc(a.text) : "只当背景 · 第 VI 层起主场才生效", !s.arenaActive)}
      </div>
      <div class="facts">${facts}</div>
      <div class="vn-learn"><small>这一层新学的</small>${esc(s.teaches)}</div>
      ${s.demon ? `<div class="vn-prize"><span class="demon got mini" style="--sin:${stageColor(s)}"><span>${s.demon}</span></span>赢了得到她的魔神牌，再从 3 名人物里挑 1 名进牌池</div>` : ""}
    </div>
    ${dialog(s, s.intro, `${tries ? `<div class="tally" title="输给她 ${tries} 次">${"<i></i>".repeat(Math.min(tries, 12))}${tries > 12 ? `<small>×${tries}</small>` : ""}</div>` : ""}
      ${warn}
      <div class="gate-actions row vn-actions">
        ${saved ? `<button class="big" data-go="enter" data-arg="${no}">重新开始</button><button class="primary big" data-go="resumeStage" autofocus>继续牌桌<small>第 ${saved.handNo} 手 · 你 ${saved.stacks[0]} 筹码</small></button>`
          : `<button class="primary big seat-btn" data-go="enter" data-arg="${no}" autofocus>入座</button>`}
      </div>`)}`;
  return scene(s, c.art, inner, "brief");
}

// ───────── 一关打完 ─────────

export function resultView(c: CampaignCtx, r: StageResult): string {
  const s = stage(r.stage);
  const next = r.stage + 1 < STAGES.length ? stage(r.stage + 1) : null;
  if (!r.won) {
    const inner = `
      <div class="vn-cast">${stageFace(s, c.art, "vn-face gloat")}</div>
      <div class="verdict lose"><small>VICTA ES</small><b>${s.foe}赢下了牌桌</b>
        <div class="tally big" title="输给她 ${r.retries} 次">${"<i></i>".repeat(Math.min(r.retries, 12))}${r.retries > 12 ? `<small>×${r.retries}</small>` : ""}</div>
        <span>你已经输给她 ${r.retries} 次</span></div>
      ${dialog(s, r.taunt ?? "", `<div class="gate-actions row vn-actions">
        <button class="big" data-go="campaign">回到炼狱之馆</button>
        <button class="primary big" data-go="enter" data-arg="${r.stage}" autofocus>再来一次</button>
      </div>`)}`;
    return scene(s, c.art, inner, "result lose");
  }
  const tries = r.retries ? `输了 ${r.retries} 次，第 ${r.retries + 1} 次才赢` : "一次就赢了";
  const go = c.progress.offer
    ? `<button class="primary big" data-go="reward" autofocus>挑一名人物 ›</button>`
    : next && r.firstClear
      ? `<button class="primary big" data-go="brief" data-arg="${next.no}" autofocus>上楼：${next.foe} ›</button>`
      : `<button class="primary big" data-go="campaign" autofocus>回到炼狱之馆</button>`;
  const ending = !next && r.firstClear ? `<p class="vn-warn good">七扇玫瑰窗都亮了。炼狱之馆的门开了。</p>` : "";
  const inner = `
    <div class="vn-cast">${stageFace(s, c.art, "vn-face beaten")}</div>
    <div class="verdict win">
      ${s.no > 0 ? `<div class="verdict-rose">${rose(stageColor(s), "lit")}</div>` : ""}
      <small>VICTORIA</small><b>你赢下了这一层</b><span>${tries}</span>
      ${r.firstClear && s.demon ? `<div class="vn-prize"><span class="demon got mini" style="--sin:${stageColor(s)}"><span>${s.demon}</span></span>得到她的魔神牌「${s.demon}」</div>` : ""}
    </div>
    ${dialog(s, s.outro, `${ending}<div class="gate-actions row vn-actions">${go}</div>`)}`;
  return scene(s, c.art, inner, "result win");
}

// ───────── 挑人 ─────────

export function rewardView(c: CampaignCtx, pick: string | null, remove: string | null): string {
  const offer = c.progress.offer;
  if (!offer) return campaignView(c);
  const s = stage(offer.stage);
  const cand = offer.ids.map((id, i) =>
    `<div class="reward-opt ${pick === id ? "on" : ""}" style="--i:${i}" data-go="rpick" data-arg="${id}" role="button" tabindex="0">${c.card(id)}</div>`).join("");
  const pool = c.progress.pool;
  const canRemove = pool.length >= MIN_CAMPAIGN_POOL;
  const mine = pool.map((id) =>
    `<div class="reward-pool ${remove === id ? "on" : ""}" ${canRemove ? `data-go="rremove" data-arg="${id}" role="button" tabindex="0" title="${remove === id ? "取消移除" : "移除这一名"}"` : ""}>${c.card(id, "small")}</div>`).join("");
  const label = rewardLabel(pick, remove);
  return `<div class="reward-stage" style="--sin:${stageColor(s)}">
    <header class="reward-head">
      <div class="discover-title">发现<small>INVENTIO · ${s.foe}的战利品</small></div>
      <p class="tower-sub">挑 1 名放进你的牌池，以后每一层都会发到。</p>
    </header>
    <div class="reward-cands">${cand}</div>
    <section class="reward-shelf">
      <h3>整理牌池<small>${canRemove ? `可以划掉 1 名，让以后的发牌更集中（至少留 ${MIN_CAMPAIGN_POOL} 名），再点一次取消` : `牌池至少要留 ${MIN_CAMPAIGN_POOL} 名，这次不能移除`}</small></h3>
      <div class="reward-mine">${mine}</div>
    </section>
    <div class="gate-actions row">
      <button class="primary big ${pick ? "" : "disabled"}" data-go="rdone" ${pick ? "" : `aria-disabled="true"`}>${label}</button>
    </div>
  </div>`;
}

export const rewardLabel = (pick: string | null, remove: string | null) =>
  pick ? (remove ? "挑好了 · 移除划掉的那名" : "挑好了 · 不移除") : "先挑一名";

/** 牌池一览。 */
export function poolView(c: CampaignCtx): string {
  return `<div class="reward-stage">
    <button class="gate-back" data-go="campaign" aria-label="返回">‹ 炼狱之馆</button>
    <header class="reward-head">
      <div class="discover-title">牌池<small>COLLEGIUM · ${c.progress.pool.length} 名</small></div>
      <p class="tower-sub">每手从这里随机发牌；每赢下一位姐妹可以挑 1 名、移除 1 名。</p>
    </header>
    <section class="reward-shelf"><div class="reward-mine">${c.progress.pool.map((id) => `<div class="reward-pool">${c.card(id, "small")}</div>`).join("")}</div></section>
  </div>`;
}

/** 牌桌顶上和规则牌上显示的专属规则名（第 7 层每手翻的是具体哪一条）。 */
export function stageRuleName(no: number, ruleId: string): string {
  const s = stage(no);
  if (s.rules.length === 1) return s.ruleName;
  const from = STAGES.find((x) => x.rules.length === 1 && x.rules[0] === ruleId);
  return `${s.ruleName} · ${from ? from.ruleName : rule(ruleId).name}`;
}

/** 规则说明：单条规则用关卡里写好的说法，第 7 层用翻到的那一条。 */
export function stageRuleText(no: number, ruleId: string): string {
  const s = stage(no);
  if (s.rules.length === 1) return s.ruleText;
  const from = STAGES.find((x) => x.rules.length === 1 && x.rules[0] === ruleId);
  return from ? from.ruleText : rule(ruleId).text;
}
