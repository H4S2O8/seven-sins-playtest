import type { CampaignProgress } from "../src/campaign/progress.js";
import { MIN_CAMPAIGN_POOL, STAGES, stage, type StageDef } from "../src/campaign/stages.js";
import { arena, rule } from "../src/content/tables.js";
import { SIN_LATIN } from "./sigil.js";
import { SIN_COLOR, esc } from "./text.js";

/**
 * 炼狱战役的几屏（画在入场那一层 #gate 里）：18+ 确认、炼狱之馆（关卡列表）、关前、一关打完、挑人。
 * 这里只生成 HTML；点击统一走 data-go，由 intro.ts 的 Gate 处理。
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

/** 这一屏之前不加载任何立绘和 CG：这里只有文字。 */
export function ageView(refused: boolean): string {
  if (refused) {
    return `<div class="gate-panel age">
      <h2>七罪暗队</h2>
      <p class="gate-sub">本游戏仅面向年满 18 岁的玩家。</p>
      <div class="gate-actions row"><button data-go="age">返回</button></div>
    </div>`;
  }
  return `<div class="gate-panel age">
    <div class="logo-latin">SEPTEM · PECCATA · MORTALIA</div>
    <h2>七罪暗队</h2>
    <p class="gate-sub">本游戏包含成人向的角色形象和剧情内容，仅面向年满 18 岁的玩家。<br>所有角色均为成年人。</p>
    <div class="gate-actions row">
      <button data-go="refuse">未满 18 岁，离开</button>
      <button class="primary big" data-go="adult" autofocus>我已年满 18 岁</button>
    </div>
  </div>`;
}

// ───────── 关卡里用到的小部件 ─────────

export const stageColor = (s: StageDef) => (s.sin ? SIN_COLOR[s.sin] : "#d9a44a");

/** 对手的半身像；还没画的用罪的纹样代替（看板娘是凡人，写 TABERNA）。 */
export function stageFace(s: StageDef, art: Set<string>, cls = ""): string {
  const img = s.portrait && art.has(s.portrait) ? `<img src="art/${s.portrait}.webp" alt="" draggable="false">` : "";
  return `<div class="hero bust ${cls}" style="--sin:${stageColor(s)}">
    <span class="hero-glyph">${s.sin ? SIN_LATIN[s.sin] : "TABERNA"}</span>${img}
  </div>`;
}

const stageLabel = (s: StageDef) => (s.no === 0 ? "序章" : `第 ${s.no} 层`);

function ruleLine(s: StageDef) {
  return `<div class="stage-rule"><b>${esc(s.ruleName)}</b><span>${esc(s.ruleText)}</span></div>`;
}

function homeLine(s: StageDef) {
  const a = arena(s.arenaId);
  return s.arenaActive
    ? `「${a.name}」：${esc(a.text)}`
    : `「${a.name}」（只当背景，第 6 层起主场才有效果）`;
}

// ───────── 炼狱之馆：关卡列表 ─────────

export function campaignView(c: CampaignCtx): string {
  const p = c.progress;
  const rows = STAGES.map((s) => {
    const open = s.no <= p.cleared;
    const done = s.no < p.cleared;
    const tries = p.retries[s.no];
    const state = done
      ? `通关${p.clearedAfter[s.no] ? ` · 重来 ${p.clearedAfter[s.no]} 次` : ""}`
      : open ? (tries ? `挑战中 · 已重来 ${tries} 次` : "挑战中") : "未解锁";
    const saved = c.saved?.stage === s.no ? `<em class="stage-saved">未打完 · 第 ${c.saved.handNo} 手</em>` : "";
    const attrs = open ? `data-go="brief" data-arg="${s.no}" role="button" tabindex="0"` : `aria-disabled="true"`;
    return `<div class="stage-row ${done ? "done" : open ? "open" : "locked"}" style="--sin:${stageColor(s)}" ${attrs}>
      ${stageFace(s, open ? c.art : new Set(), "stage-face")}
      <div class="stage-info">
        <small>${stageLabel(s)}${s.sin ? ` · ${s.sin}` : ""}</small>
        <b>${open ? s.foe : "？？？"}</b>
        <span>${open ? esc(s.ruleName) : "赢下前一层才能上楼"}</span>
      </div>
      <div class="stage-state">${state}${saved}</div>
    </div>`;
  }).join("");
  const all = p.cleared >= STAGES.length;
  const demons = p.demons.length ? `<p class="gate-sub">魔神牌：${p.demons.map(esc).join("、")}（魔神降临还没做，先只收集）</p>` : "";
  return `<div class="gate-panel wide campaign">
    <button class="gate-back" data-go="back" aria-label="返回">‹ 返回</button>
    <h2>炼狱之馆</h2>
    <p class="gate-sub">${all ? "七姐妹都输给了你。门开着，你随时可以回来再打一遍。" : "赢过七姐妹，你才能离开。每一层都打到一方输光筹码；输了可以无限重来。"}</p>
    ${demons}
    <div class="stage-list">${rows}</div>
    <div class="gate-actions row">
      <button data-go="pool">我的牌池（${p.pool.length}）</button>
      ${p.offer ? `<button class="primary big" data-go="reward">挑人<small>打败${stage(p.offer.stage).foe}的奖励还没领</small></button>` : ""}
    </div>
  </div>`;
}

// ───────── 关前 ─────────

export function briefView(c: CampaignCtx, no: number): string {
  const s = stage(no);
  const p = c.progress;
  const tries = p.retries[no];
  const saved = c.saved?.stage === no ? c.saved : null;
  const table = s.betting
    ? `各带 <b>${s.buyIn}</b> 筹码 · 底注 <b>${s.baseAnte}</b> 起，每 ${s.blindEvery} 手翻倍 · 各发 ${s.deal} 张挑 3 张`
    : `各带 <b>${s.buyIn}</b> 筹码 · 每手固定押 <b>${s.baseAnte}</b>，不下注 · 各发 3 张全部上场，只排位置`;
  const replay = no < p.cleared ? `<p class="gate-warn">你已经赢过她了：重打不会再给奖励。</p>` : "";
  const other = c.saved && c.saved.stage !== no ? `<p class="gate-warn">开这一关会放弃你在「${stage(c.saved.stage).foe}」那一层没打完的牌桌。</p>` : "";
  return `<div class="gate-panel brief" style="--sin:${stageColor(s)}">
    <button class="gate-back" data-go="campaign" aria-label="返回">‹ 炼狱之馆</button>
    <div class="brief-head">
      ${stageFace(s, c.art, "brief-face")}
      <div>
        <small>${stageLabel(s)}${s.sin ? ` · ${s.sin}` : ""}</small>
        <h2>${s.foe}</h2>
        <p class="brief-title">${esc(s.title)}</p>
        <q class="brief-line">${esc(s.intro)}</q>
      </div>
    </div>
    <div class="brief-body">
      <div class="brief-item"><span>专属规则</span><div>${ruleLine(s)}</div></div>
      <div class="brief-item"><span>这一层新学的</span><div>${esc(s.teaches)}</div></div>
      <div class="brief-item"><span>牌桌</span><div>${table}</div></div>
      <div class="brief-item"><span>主场</span><div>${homeLine(s)}</div></div>
      ${s.demon ? `<div class="brief-item"><span>赢了得到</span><div>她的魔神牌「${s.demon}」，再从 3 名人物里挑 1 名进牌池</div></div>` : ""}
      ${tries ? `<div class="brief-item"><span>重来</span><div>已经输给她 ${tries} 次</div></div>` : ""}
    </div>
    ${replay}${other}
    <div class="gate-actions row">
      ${saved ? `<button data-go="enter" data-arg="${no}">重新开始</button><button class="primary big" data-go="resumeStage" autofocus>继续牌桌<small>第 ${saved.handNo} 手 · 你 ${saved.stacks[0]} 筹码</small></button>`
        : `<button class="primary big" data-go="enter" data-arg="${no}" autofocus>入座 ›</button>`}
    </div>
  </div>`;
}

// ───────── 一关打完 ─────────

export function resultView(c: CampaignCtx, r: StageResult): string {
  const s = stage(r.stage);
  const next = r.stage + 1 < STAGES.length ? stage(r.stage + 1) : null;
  if (!r.won) {
    return `<div class="gate-panel result lose" style="--sin:${stageColor(s)}">
      ${stageFace(s, c.art, "brief-face")}
      <h2>${s.foe}赢下了牌桌</h2>
      <q class="taunt">${esc(r.taunt ?? "")}</q>
      <p class="gate-sub">你已经输给她 ${r.retries} 次。${esc(s.ruleName)}：${esc(s.ruleText)}</p>
      <div class="gate-actions row">
        <button data-go="campaign">回到炼狱之馆</button>
        <button class="primary big" data-go="enter" data-arg="${r.stage}" autofocus>再来一次</button>
      </div>
    </div>`;
  }
  const tries = r.retries ? `第 ${r.retries + 1} 次才赢，你还挺能坚持。` : "一次就赢了。";
  const reward = r.firstClear && s.demon ? `<p class="gate-sub">得到魔神牌「${s.demon}」。</p>` : "";
  const go = c.progress.offer
    ? `<button class="primary big" data-go="reward" autofocus>挑一名人物 ›</button>`
    : next && r.firstClear
      ? `<button class="primary big" data-go="brief" data-arg="${next.no}" autofocus>上楼：${next.foe} ›</button>`
      : `<button class="primary big" data-go="campaign" autofocus>回到炼狱之馆</button>`;
  const ending = !next && r.firstClear ? `<p class="gate-sub">七姐妹都输给了你。炼狱之馆的门开了。</p>` : "";
  return `<div class="gate-panel result win" style="--sin:${stageColor(s)}">
    ${stageFace(s, c.art, "brief-face")}
    <h2>你赢下了这一层</h2>
    <q class="taunt">${esc(s.outro)}</q>
    <p class="gate-sub">${tries}</p>
    ${reward}${ending}
    <div class="gate-actions row">${go}</div>
  </div>`;
}

// ───────── 挑人 ─────────

export function rewardView(c: CampaignCtx, pick: string | null, remove: string | null): string {
  const offer = c.progress.offer;
  if (!offer) return campaignView(c);
  const s = stage(offer.stage);
  const cand = offer.ids.map((id) => `<div class="reward-opt ${pick === id ? "on" : ""}" data-go="rpick" data-arg="${id}" role="button" tabindex="0">${c.card(id, "small")}</div>`).join("");
  const pool = c.progress.pool;
  const canRemove = pool.length >= MIN_CAMPAIGN_POOL;
  const mine = pool.map((id) => `<div class="reward-pool ${remove === id ? "on" : ""}" ${canRemove ? `data-go="rremove" data-arg="${id}" role="button" tabindex="0"` : ""}>${c.card(id, "small")}</div>`).join("");
  return `<div class="gate-panel wide reward" style="--sin:${stageColor(s)}">
    <h2>挑一名人物</h2>
    <p class="gate-sub">从 3 名里挑 1 名放进你的牌池，以后每一层都会发到。</p>
    <div class="reward-cands">${cand}</div>
    <h2 class="reward-sub">要不要移除一名？</h2>
    <p class="gate-sub">${canRemove ? `可以从牌池里移除 1 名，让以后的发牌更集中（牌池至少留 ${MIN_CAMPAIGN_POOL} 名）。再点一次取消。` : `牌池至少要留 ${MIN_CAMPAIGN_POOL} 名，这次不能移除。`}</p>
    <div class="reward-mine">${mine}</div>
    <div class="gate-actions row">
      <button class="primary big ${pick ? "" : "disabled"}" data-go="rdone" ${pick ? "" : "aria-disabled=\"true\""}>${pick ? (remove ? "挑好了，移除选中的那名" : "挑好了，不移除") : "先挑一名"}</button>
    </div>
  </div>`;
}

/** 牌池一览。 */
export function poolView(c: CampaignCtx): string {
  return `<div class="gate-panel wide reward">
    <button class="gate-back" data-go="campaign" aria-label="返回">‹ 炼狱之馆</button>
    <h2>我的牌池</h2>
    <p class="gate-sub">${c.progress.pool.length} 名。每手从这里随机发牌；每赢下一位姐妹可以挑 1 名、移除 1 名。</p>
    <div class="reward-mine">${c.progress.pool.map((id) => `<div class="reward-pool">${c.card(id, "small")}</div>`).join("")}</div>
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
