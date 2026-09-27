import type { Style } from "../src/ai/agents.js";
import type { NumericAction, NumericObservation } from "../src/numeric/types.js";
import { character } from "../src/content/characters.js";
import { characterById, equipmentById, arenaById, ruleById, effectById, type NumericEquipmentTier } from "../src/numeric/content.js";
import { esc, SIN_COLOR } from "./text.js";
import { cardArt } from "./campaign.js";
import { currentFrame } from "./frames.js";
import { flip, measure, reducedMotion, strike, pulse } from "./motion.js";
import { morph } from "./morph.js";
import { relight } from "./light.js";
import { SIN_LATIN } from "./sigil.js";
import { isMuted, toggleMuted, setScene } from "./music.js";

/**
 * 独立的单数值牌桌界面。它只依赖 NumericTable 的观察层和动作入口，
 * 不读取旧 Table 的内部状态，因此可以和朋友的战役、自由牌桌并存。
 */
export interface NumericTableLike {
  observe(seat: 0 | 1): NumericObservation;
  apply(seat: 0 | 1, action: NumericAction): void;
  aiAction?(seat: 1, style: Style): NumericAction | null;
}

export interface NumericModeHooks {
  create(style: Style): NumericTableLike;
  exit(): void;
  art: Set<string>;
}

const TUTORIAL_KEY = "sinsquad.numeric.tutorial.v1";
const readTutorial = () => { try { return localStorage.getItem(TUTORIAL_KEY) === "1"; } catch { return false; } };
const saveTutorial = () => { try { localStorage.setItem(TUTORIAL_KEY, "1"); } catch { /* 无痕模式不影响游玩 */ } };

const styleName: Record<Style, string> = { cautious: "谨慎的税官", aggressive: "激进的挑衅者", bluff: "爱诈唬的魅惑者" };
const phaseName: Record<string, string> = {
  draft: "九选三 / D 一次", place: "数字与效果排位", bet: "下注", operate: "操作费与装备", equip: "安装装备",
  vote: "场地效果表决", bid: "场地效果暗标", result: "结算", over: "牌桌结束",
};

function effectName(id: string): string {
  return characterById(id).name;
}
function effectText(id: string): string {
  return characterById(id).text;
}
function installLabel(x: { id: string; tier: string } | null): string {
  if (!x) return "空位";
  return `${equipmentById(x.id, x.tier as NumericEquipmentTier).name} · ${x.tier === "normal" ? "常规" : x.tier === "replace-1" ? "替换Ⅰ" : "替换Ⅱ"}`;
}
function lookUp<T extends { id: string; name: string; text: string }>(fn: (id: string) => T, id: string): T {
  try { return fn(id); } catch { return { id, name: id, text: "该环境效果的详细文本将在揭示时显示" } as T; }
}

export class NumericMode {
  private readonly root: HTMLElement;
  private table: NumericTableLike | null = null;
  private style: Style = "cautious";
  private tutorialOpen = !readTutorial();
  private tutorialPage = 0;
  private error = "";
  private amount = 5;
  private selectedEffects: number[] = [0, 1, 2];
  private selectedNumbers: number[] = [0, 1, 2];
  private aiTimer: number | null = null;
  private layoutHand = -1;
  private outcomeHand = -1;
  private replayLine = -1;
  private replaying = false;
  private replayToken = 0;
  private detail: { title: string; text: string } | null = null;
  private readonly hover: HTMLElement;
  private readonly tutorial = [
    ["你要赢的是筹码", "双方带相同筹码入座。每手先交底注形成奖池，赢家获得这手的奖池。一张牌桌由多手组成，直到一方筹码用完。下面先学怎么组队，再学怎么下注。"],
    ["先收到三张数字", "三张原始数字直接随机发给你，不能选、不能重抽。数字代表基础力量，人物没有攻击与血量两套数值。大数正面较强，小数可能通过克制、乘法或邻位配合反超。"],
    ["对手究竟知道什么", "你知道自己的三个精确数字；对手只知道这三个数字的高、中、低构成，构成的排列不对应桌上的位置。双方都看不到对方人物效果、效果候选和装备候选。装好的装备及安装位置公开。"],
    ["先读公开环境", "数字发出后，基础场地和胜利规则公开，再挑人物效果。基础场地调整数字或位置价值；胜利规则决定这手怎样判赢家。三张额外效果会在前三轮逐张决定是否生效。高牌阵容或小牌阵容可能有优势，但不会只凭牌型自动获胜。"],
    ["九张效果里留下三张", "初始发九张不同的人物效果。点击卡牌锁定，最多保留三张。你可以直接留三张；也可以先留零、一或两张，再使用一次 D。看不到第二批候选时，就必须决定第一批留下什么。"],
    ["D 是一次不可回头的决定", "D 会永久刷走本批所有未留下的效果，保留的效果锁定。新发九张候选不包含已刷走和已保留的牌，之后从新一批补足三张。支持 0+3、1+2、2+1、3+0；D 不重抽你的数字。"],
    ["数字、人物、顺序独立组合", "三张数字和三个人物效果各用一次。你可以交换数字，让同一人物拿到另一个数字；也可以交换人物位置，让效果针对另一条线。确认以后同时暗中锁定，看到装备后不能重新排人。"],
    ["固定对位，靠效果针对", "1号位只和敌方1号位比，2对2、3对3。若猜敌方2号位是小数，可以把针对小数的人物放在你的2号位。原始数字指发牌时的数；当前力量指效果按顺序计算到当时的数。请以每张卡写明的条件为准。"],
    ["下注、跟注、加注、弃牌", "无人下注时可以过牌，或下注开价；有人下注后，你可以补齐差额跟注、提高本轮总额加注，或弃牌放弃奖池。加注输入的是“加到多少”，不是“再加多少”。已经投入的筹码不会因弃牌退还。"],
    ["拿装备还有操作费", "双方本轮下注跟齐后，可以额外付操作费拿装备。操作费显示在按钮上，付费后从三张候选选一件并选位置。双方安装决定锁定后一起公开；你可以不拿。前三轮是普通装备，只能装空位，一位最多一件。"],
    ["额外效果由你们争取", "前三轮各处理一张额外效果。双方暗中投“启用”或“不启用”；意见一致直接确定，意见不同再暗标竞拍。出价在双方提交前保密，确定后的效果状态持续到本手结束。"],
    ["替换装备是有限补救", "第4、5轮只发第一档替换版，第6、7轮发更弱的第二档替换版。它们是相同装备机制的低数值版本，可以覆盖已有装备或装到空位。覆盖后旧装备彻底失效。数值档位只影响新拿的牌，已经装好的装备不会自己衰减。"],
    ["什么时候开战", "前三轮双方都过牌、不拿装备，也要处理完三张额外效果。从第4轮起，某整轮双方都没追加筹码、没拿装备，就开战。第7轮后不再拿装备，但仍能继续加注；没有人继续加钱时开战。"],
    ["全押与提前结束", "全押后，对手仍可弃牌或跟注。跟注后退回无法匹配的超额，立即开战：已确定的额外效果保留，尚未定夺的一律关闭，后续装备窗口取消。全押会锁定当前环境，使用前先看清提示。"],
    ["看清为什么赢", "开战才揭开双方精确数字、人物效果与排列。各效果按固定阶段结算，然后三条线分别比较最终力量，最后按本手公开的胜利规则判定。查看结算明细可追溯每次修正；所有相等和特殊条件也以本手胜利规则为准。"],
    ["现在开始，随时可回来", "先看自己的数字和场地，再挑互相配合的效果。悬停或点详情可读完整卡面；不要只看牌名。顶栏“教程”可随时重新打开，本次读完后以后进入不再强制。"],
  ] as const;

  constructor(private readonly hooks: NumericModeHooks) {
    this.root = document.createElement("div");
    this.root.id = "numeric-mode";
    this.hover = document.createElement("aside");
    this.hover.id = "numeric-hover";
    this.hover.setAttribute("role", "tooltip");
    document.body.appendChild(this.hover);
    this.root.addEventListener("click", (ev) => {
      const el = (ev.target as HTMLElement).closest<HTMLElement>("[data-nact]");
      if (!el || el.classList.contains("disabled")) return;
      this.onAction(el.dataset.nact!, el.dataset.arg);
    });
    this.root.addEventListener("input", (ev) => {
      const el = ev.target as HTMLInputElement;
      if (el.dataset.ninput === "amount") {
        this.amount = Math.max(0, Math.floor(Number(el.value) || 0));
        this.root.querySelectorAll<HTMLElement>("[data-amount]").forEach((x) => { x.textContent = String(this.amount); });
      }
    });
    this.root.addEventListener("change", (ev) => {
      const el = ev.target as HTMLSelectElement;
      const i = Number(el.dataset.index);
      if (!Number.isInteger(i) || i < 0 || i > 2) return;
      const mapping = el.dataset.nselect === "e" ? this.selectedEffects : el.dataset.nselect === "n" ? this.selectedNumbers : null;
      if (!mapping) return;
      const picked = Number(el.value), at = mapping.indexOf(picked);
      [mapping[i], mapping[at]] = [mapping[at], mapping[i]];
      this.draw();
    });
    this.root.addEventListener("keydown", (ev) => {
      if (ev.key === "Escape" && this.detail) { this.detail = null; return this.draw(); }
      const el = (ev.target as HTMLElement).closest<HTMLElement>("[data-nact][role=button]");
      if ((ev.key === "Enter" || ev.key === " ") && el) { ev.preventDefault(); this.onAction(el.dataset.nact!, el.dataset.arg); }
    });
    this.root.addEventListener("pointermove", (ev) => {
      const el = (ev.target as HTMLElement).closest<HTMLElement>("[data-ntitle]");
      if (!el || this.tutorialOpen || this.detail) { this.hover.style.display = "none"; return; }
      this.hover.innerHTML = `<b>${esc(el.dataset.ntitle ?? "")}</b><p>${esc(el.dataset.ntext ?? "")}</p>`;
      this.hover.style.display = "block";
      const w = this.hover.offsetWidth, h = this.hover.offsetHeight;
      this.hover.style.left = `${Math.min(Math.max(8, ev.clientX + 14), window.innerWidth - w - 8)}px`;
      this.hover.style.top = `${Math.min(Math.max(8, ev.clientY + 18), window.innerHeight - h - 8)}px`;
    });
    this.root.addEventListener("pointerleave", () => { this.hover.style.display = "none"; });
    document.body.appendChild(this.root);
  }

  start(style: Style) {
    this.style = style;
    this.table = this.hooks.create(style);
    this.tutorialOpen = !readTutorial();
    this.tutorialPage = 0;
    this.layoutHand = -1;
    this.outcomeHand = -1;
    this.detail = null;
    this.error = "";
    this.replaying = false;
    this.replayToken++;
    setScene("bet", "numeric-table");
    const old = document.querySelector<HTMLElement>("#app");
    old?.classList.add("numeric-hidden");
    this.draw();
    this.runAi();
  }

  exit() {
    if (this.aiTimer !== null) window.clearTimeout(this.aiTimer);
    this.aiTimer = null;
    this.table = null;
    this.replayToken++;
    this.replaying = false;
    this.hover.style.display = "none";
    this.root.innerHTML = "";
    this.root.classList.remove("open");
    document.querySelector<HTMLElement>("#app")?.classList.remove("numeric-hidden");
    this.hooks.exit();
  }

  private obs(): NumericObservation | null { return this.table?.observe(0) ?? null; }
  private runAi() {
    if (!this.table || this.tutorialOpen || this.aiTimer !== null) return;
    const o = this.obs();
    if (!o || o.phase === "over" || o.phase === "result" || !this.table.aiAction || !o.toAct.includes(1)) return;
    this.aiTimer = window.setTimeout(() => {
      this.aiTimer = null;
      if (!this.table || this.tutorialOpen) return;
      try {
        if (this.table.observe(0).toAct.includes(1)) {
          const a = this.table.aiAction?.(1, this.style);
          if (a) this.table.apply(1, a);
        }
      } catch (e) { this.error = e instanceof Error ? e.message : String(e); }
      this.draw();
      this.runAi();
    }, reducedMotion() ? 40 : 260);
  }

  private send(action: NumericAction) {
    if (!this.table) return;
    try {
      this.table.apply(0, action);
      this.error = "";
      this.runAi();
      this.draw();
    } catch (e) { this.error = e instanceof Error ? e.message : String(e); this.draw(); }
  }

  private onAction(type: string, arg?: string) {
    if (type === "exit") return this.exit();
    if (type === "tutorial") { this.tutorialOpen = true; this.tutorialPage = 0; return this.draw(); }
    if (type === "tutorialNext") {
      if (this.tutorialPage + 1 >= this.tutorial.length) { this.tutorialOpen = false; saveTutorial(); }
      else this.tutorialPage++;
      this.draw(); this.runAi(); return;
    }
    if (type === "tutorialPrev") { this.tutorialPage = Math.max(0, this.tutorialPage - 1); return this.draw(); }
    if (type === "music") { toggleMuted(); return this.draw(); }
    if (type === "info") { const el = this.root.querySelector<HTMLElement>(`[data-info="${arg}"]`); if (el) this.detail = { title: el.dataset.ntitle ?? "详情", text: el.dataset.ntext ?? "" }; return this.draw(); }
    if (type === "closeInfo") { this.detail = null; return this.draw(); }
    if (this.tutorialOpen) return;
    if (type === "replay") { this.outcomeHand = -1; return this.draw(); }
    if (type === "keep" || type === "reroll") return this.send(type === "keep" ? { type, index: Number(arg) } : { type });
    if (type === "place") return this.send({ type, effects: this.selectedEffects as [number, number, number], numbers: this.selectedNumbers as [number, number, number] });
    if (type === "bet") return this.send({ type: "bet", amount: this.amount });
    if (type === "raise") return this.send({ type: "raise", to: this.amount });
    if (type === "bid") return this.send({ type: "bid", amount: this.amount });
    if (type === "equip") { const [offerIndex, pos] = (arg ?? "0,0").split(",").map(Number); return this.send({ type: "equip", offerIndex, pos }); }
    if (type === "operate") return this.send({ type: "operate", draft: arg === "1" });
    if (type === "vote") return this.send({ type: "vote", activate: arg === "1" });
    if (type === "next") return this.send({ type: "nextHand" });
    if (["check", "call", "allIn", "fold"].includes(type)) return this.send({ type } as NumericAction);
  }

  private draw() {
    const o = this.obs();
    this.root.classList.add("open");
    if (!o) { this.root.innerHTML = ""; return; }
    if (this.layoutHand !== o.handNo) { this.layoutHand = o.handNo; this.selectedEffects = [0, 1, 2]; this.selectedNumbers = [0, 1, 2]; this.replayLine = -1; }
    const before = measure(this.root);
    morph(this.root, `${this.header(o)}${this.environment(o)}${this.board(o)}${this.error ? `<p class="numeric-error" role="alert">${esc(this.error)}</p>` : ""}${this.dock(o)}${this.tutorialOpen ? this.tutorialView() : ""}${this.detail ? `<div class="numeric-tutorial"><div class="numeric-tutorial-panel" role="dialog" aria-modal="true"><h2>${esc(this.detail.title)}</h2><p>${esc(this.detail.text)}</p><button data-nact="closeInfo">关闭详情</button></div></div>` : ""}`);
    flip(this.root, before);
    relight();
    if (o.result?.teams && this.outcomeHand !== o.handNo && !this.replaying) void this.playComparison(o);
  }

  private header(o: NumericObservation) {
    return `<header class="numeric-top"><b>七宗罪-德州战棋</b><span>第 ${o.handNo} 手 · 第 ${o.round} 轮 · ${styleName[this.style]}</span><span class="numeric-stacks">你 ${o.stacks[0]} · 对手 ${o.stacks[1]} · 奖池 ${o.pot}</span><button data-nact="music">♪ ${isMuted() ? "关" : "开"}</button><button data-nact="tutorial">教程</button><button data-nact="exit">返回主菜单</button></header>`;
  }

  private environment(o: NumericObservation) {
    const arena = o.arenaId ? lookUp(arenaById, o.arenaId) : null;
    const rule = o.ruleId ? lookUp(ruleById, o.ruleId) : null;
    const fx = o.effects.map((x, i) => { const d = lookUp(effectById, x.id); return `<div class="numeric-env-effect ${x.status}" data-ntitle="${esc(d.name)}" data-ntext="${esc(d.text)}"><small>额外效果 ${i + 1}</small><b>${esc(d.name)}</b><span>${x.status === "active" ? "已启用" : x.status === "inactive" ? "未启用" : "待定"}</span></div>`; }).join("");
    return `<section class="numeric-environment"><button class="numeric-env-card" data-nact="info" data-arg="arena" data-info="arena" data-ntitle="${esc(arena?.name ?? "基础场地")}" data-ntext="${esc(arena?.text ?? "尚未揭示")}"><small>基础场地</small><b>${esc(arena?.name ?? "尚未揭示")}</b></button><button class="numeric-env-card" data-nact="info" data-arg="rule" data-info="rule" data-ntitle="${esc(rule?.name ?? "胜利规则")}" data-ntext="${esc(rule?.text ?? "尚未揭示")}"><small>胜利规则</small><b>${esc(rule?.name ?? "尚未揭示")}</b></button>${fx}</section>`;
  }

  private board(o: NumericObservation) {
    const revealed = o.result?.teams;
    const foe = [0, 1, 2].map((i) => this.slotCard(revealed?.[1]?.[i] ?? null, i, 1, o)).join("");
    const prepared = o.phase === "place" && o.me.kept.length === 3
      ? this.selectedEffects.map((e, i) => ({ effectId: o.me.kept[e], number: o.me.numbers[this.selectedNumbers[i]] })) : null;
    const mine = (revealed?.[0] ?? o.me.slots ?? prepared)?.map((x, i) => this.slotCard(x, i, 0, o)).join("") ?? `<div class="numeric-numbers">已发给你的原始数字${o.me.numbers.map((n) => `<b>${n}</b>`).join(" ")}<p>这三张不能重抽 · 接下来选择与它们组合的人物效果</p></div>`;
    const composition = o.opponent.tiers.map((x) => x === "low" ? "低" : x === "mid" ? "中" : x === "high" ? "高" : x).join(" · ");
    return `<main class="numeric-board"><section><h3>对手</h3><div class="numeric-composition" data-ntitle="对手原始数字构成" data-ntext="构成不对应1、2、3号位。对手的精确数字、排位和人物效果在战斗前隐藏。">构成：${esc(composition)}<small>仅知构成，不知位置</small></div><div class="numeric-slots foe-slots">${foe}</div></section><div class="numeric-vs">VS<div class="numeric-phase">${esc(phaseName[o.phase] ?? o.phase)}</div></div><section><h3>你</h3><div class="numeric-slots">${mine}</div></section></main>`;
  }

  private slotCard(x: {effectId: string; number: number} | null, i: number, seat: 0|1, o: NumericObservation) {
    const eq = (seat === 0 ? o.me.equipment : o.opponent.equipment)[i] ?? null;
    const pow = o.result?.powers?.[seat]?.[i];
    const infoId = `slot-${seat}-${i}`;
    let art = "", sin = "#6a5640";
    if (x) { const c = character(x.effectId), a = cardArt(x.effectId); sin = SIN_COLOR[c.sin]; if (this.hooks.art.has(a)) art = `<img src="art/${a}.webp" alt="" draggable="false">`; }
    const detail = x ? `${effectText(x.effectId)}${eq ? `\n装备公开：${equipmentById(eq.id, eq.tier as NumericEquipmentTier).text}` : ""}` : "人物和精确数字在战斗前隐藏。装备及其安装位置公开。";
    return `<div class="numeric-slot ${seat === 1 ? "foe-slot" : ""} ${x ? "revealed" : "concealed"}" data-key="numeric-${o.handNo}-${seat}-${i}" data-unit="${seat}-${i}" style="--sin:${sin}" data-info="${infoId}" data-ntitle="${esc(x ? effectName(x.effectId) : "隐藏人物")}" data-ntext="${esc(detail)}"><small>${i+1}号位</small><div class="numeric-slot-art">${art || `<span>${x ? "" : "?"}</span>`}</div><b>${esc(x ? effectName(x.effectId) : o.opponent.placed ? "已暗置" : "等待布阵")}</b><span class="numeric-slot-power">${x ? pow !== undefined ? `原数 ${x.number} → 力量 ${pow}` : `原始数字 ${x.number}` : "数字 · 效果隐藏"}</span>${this.equipPill(eq)}<button class="numeric-info" data-nact="info" data-arg="${infoId}">详情</button></div>`;
  }

  private equipPill(x: { id: string; tier: string } | null) { return x ? `<span class="numeric-equip" data-ntitle="${esc(installLabel(x))}" data-ntext="${esc(equipmentById(x.id, x.tier as NumericEquipmentTier).text)}">${esc(installLabel(x))}</span>` : `<span class="numeric-equip empty">未安装装备</span>`; }

  private draftDock(o: NumericObservation) {
    const cards = o.me.current.map((id, i) => this.effectCard(id, i, o.me.kept.includes(id))).join("");
    const kept = o.me.kept.map((id) => `<span data-ntitle="${esc(effectName(id))}" data-ntext="${esc(effectText(id))}">${esc(effectName(id))}</span>`).join("");
    return `<section class="numeric-dock"><h3>候选人物效果 · 已锁 ${o.me.kept.length}/3</h3><p class="numeric-hint">${o.me.rerolled ? "D 已使用，旧牌不会回来。请从新候选补满三张。" : "先锁 0～3 张，可 D 一次。锁满三张后进入排位。"}</p><div class="numeric-kept">已留：${kept || "还没选择"}</div><div class="numeric-cards">${cards}</div><div class="numeric-actions">${!o.me.rerolled && o.me.kept.length < 3 ? `<button class="primary" data-nact="reroll">D 一次（刷走未锁定牌）</button>` : ""}</div></section>`;
  }

  private effectCard(id: string, index: number, selected: boolean) {
    let sin = "#6a5640", art = "";
    try {
      const c = character(id);
      sin = SIN_COLOR[c.sin];
      const a = cardArt(id);
      art = this.hooks.art.has(a) ? `<img src="art/${esc(a)}.webp" alt="" draggable="false">` : "";
    } catch { /* 新内容中没有旧卡面时仍显示文字卡 */ }
    return `<div class="numeric-effect-card ${selected ? "selected" : ""}" data-nact="keep" data-arg="${index}" role="button" tabindex="0" data-info="${esc(id)}" data-ntitle="${esc(effectName(id))}" data-ntext="${esc(effectText(id))}" style="--sin:${sin}" data-key="offer-${id}"><span class="numeric-effect-art">${art}</span><b>${esc(effectName(id))}</b><small>${selected ? "已锁定" : "点击锁定"}</small><span>${esc(effectText(id))}</span><button class="numeric-details" data-nact="info" data-arg="${esc(id)}">查看详情</button></div>`;
  }

  private placeDock(o: NumericObservation) {
    const rows = [0, 1, 2].map((i) => {
      const es = o.me.kept.map((id, j) => `<option value="${j}" ${this.selectedEffects[i] === j ? "selected" : ""}>${esc(effectName(id))}</option>`).join("");
      const ns = o.me.numbers.map((n, j) => `<option value="${j}" ${this.selectedNumbers[i] === j ? "selected" : ""}>第${j+1}张 · ${n}</option>`).join("");
      return `<label>${i + 1}号位：人物 <select aria-label="${i+1}号位人物" data-nselect="e" data-index="${i}">${es}</select> 数字 <select aria-label="${i+1}号位数字" data-nselect="n" data-index="${i}">${ns}</select></label>`;
    }).join("");
    return `<section class="numeric-dock"><h3>自由配对数字与效果</h3><p class="numeric-hint">改变选项会和原所在位置交换，三个人物及三张数字各用一次。下方确认前可以自由调整。</p><div class="numeric-place-form">${rows}</div><button class="primary" data-nact="place">锁定三个位置</button></section>`;
  }

  private bettingDock(o: NumericObservation) {
    const call = o.betting.toCall > 0 ? `<button class="call" data-nact="call">跟注 ${o.betting.toCall}</button>` : `<button data-nact="check">过牌</button>`;
    return `<section class="numeric-dock"><h3>下注 · 目标 ${o.betting.target} · 本轮投入 ${o.betting.roundBet[0]}</h3><div class="numeric-bet-form"><input type="number" min="0" step="1" data-ninput="amount" value="${this.amount}"><button data-nact="bet">下注</button><button class="raise" data-nact="raise">加到 ${this.amount}</button>${call}<button class="allin" data-nact="allIn">全押</button><button class="fold" data-nact="fold">弃牌</button></div></section>`;
  }

  private equipDock(o: NumericObservation) {
    const tier = o.round <= 3 ? "normal" : o.round <= 5 ? "replace-1" : "replace-2";
    const offers = o.me.offers?.map((id, i) => [id, i] as const).map(([id, i]) => { const e = equipmentById(id, tier as NumericEquipmentTier); return `<div class="numeric-offer" data-ntitle="${esc(e.name)}" data-ntext="${esc(e.text)}"><b>${esc(installLabel({ id, tier }))}</b><span>${esc(e.text)}</span><div>${[0, 1, 2].map((p) => `<button data-nact="equip" data-arg="${i},${p}">装到 ${p + 1}号位</button>`).join("")}</div></div>`; }).join("") ?? "";
    return `<section class="numeric-dock"><h3>装备（公开安装）</h3><div class="numeric-offers">${offers}</div><button data-nact="operate" data-arg="0">不拿装备，继续</button></section>`;
  }

  private dock(o: NumericObservation) {
    if (o.result || o.phase === "result" || o.phase === "over") return this.resultDock(o);
    if (o.phase === "draft") return this.draftDock(o);
    if (o.phase === "place") return this.placeDock(o);
    if (o.phase === "bet") return this.bettingDock(o);
    if (o.phase === "operate") return `<section class="numeric-dock"><h3>第 ${o.round} 轮 · 装备机会</h3><p>你可以看三张装备并安装一张，也可以不拿。前三轮是普通装备；第4—7轮是逐渐变弱的替换装备。</p><button class="primary" data-nact="operate" data-arg="1">看装备</button><button data-nact="operate" data-arg="0">不拿装备</button></section>`;
    if (o.phase === "equip") return this.equipDock(o);
    if (o.phase === "vote") return `<section class="numeric-dock"><h3>额外效果是否生效</h3><button class="primary" data-nact="vote" data-arg="1">启用</button><button data-nact="vote" data-arg="0">不启用</button></section>`;
    if (o.phase === "bid") return `<section class="numeric-dock"><h3>暗标决定额外效果</h3><input type="number" data-ninput="amount" value="${this.amount}"><button class="primary" data-nact="bid">出价</button></section>`;
    return `<section class="numeric-dock"><p>等待双方锁定……</p></section>`;
  }

  private resultDock(o: NumericObservation) {
    const r = o.result;
    const lines = r?.trace?.map((x) => `<li>${esc(typeof x === "string" ? x : `${x.stage}：${x.text}（${x.before} → ${x.after}）`)}</li>`).join("") ?? r?.lines?.map((x) => `<li>${esc(x)}</li>`).join("") ?? "";
    const winner = r?.winner === 0 ? "你赢了" : r?.winner === 1 ? "对手获胜" : "平局";
    return `<section class="numeric-dock numeric-result"><h2>${winner}</h2><ol>${lines}</ol>${o.phase !== "over" ? `<button class="primary" data-nact="next">下一手</button>` : `<button data-nact="exit">回到开始界面</button>`}</section>`;
  }

  /** 结算回放：先逐条高亮三条固定对位线，再留下完整公式日志。 */
  private async playComparison(o: NumericObservation) {
    if (!o.result?.powers) return;
    this.outcomeHand = o.handNo;
    this.replaying = true;
    const token = this.replayToken;
    for (let i = 0; i < 3; i++) {
      if (token !== this.replayToken || !this.root.isConnected) return;
      this.replayLine = i;
      const slots = this.root.querySelectorAll<HTMLElement>(".numeric-slot");
      slots[i]?.classList.add("numeric-clash");
      slots[i + 3]?.classList.add("numeric-clash");
      await new Promise<void>((resolve) => window.setTimeout(resolve, reducedMotion() ? 80 : 620));
      slots[i]?.classList.remove("numeric-clash");
      slots[i + 3]?.classList.remove("numeric-clash");
    }
    this.replaying = false;
    this.draw();
  }

  private tutorialView() {
    const [title, body] = this.tutorial[this.tutorialPage];
    return `<div class="numeric-tutorial"><div class="numeric-tutorial-panel"><small>新手教程 ${this.tutorialPage + 1}/${this.tutorial.length}</small><h2>${esc(title)}</h2><p>${esc(body)}</p><div class="numeric-tutorial-actions">${this.tutorialPage ? `<button data-nact="tutorialPrev">上一步</button>` : ""}<button class="primary" data-nact="tutorialNext">${this.tutorialPage + 1 === this.tutorial.length ? "开始对战" : "下一步"}</button></div></div></div>`;
  }
}
