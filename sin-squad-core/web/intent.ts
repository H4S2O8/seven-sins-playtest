import { IntentSession, type IntentSave } from "../src/intent/session.js";
import {
  analyse,
  compactAnalysis,
  publicAnalysis,
  planText,
  BASIC_TEXT,
} from "../src/intent/analysis.js";
import {
  card,
  gear,
  plans,
  FIELDS,
  sinOf,
  INTENT_RULESET,
} from "../src/intent/content.js";
import {
  OFF,
  type Action,
  type Observation,
  type Plan,
  type Unit,
} from "../src/intent/types.js";
import type { Style } from "../src/ai/agents.js";
import { cardShell } from "./card-shell.js";
import { cardArt } from "./campaign.js";
import { currentFrame } from "./frames.js";
import { esc, SIN_COLOR } from "./text.js";
import { SIN_LATIN } from "./sigil.js";
import { relight } from "./light.js";
import { setScene, isMuted, toggleMuted } from "./music.js";
declare const __INTENT_WORKER__: string;

const SAVE = "sinsquad.intent.save.v4",
  TUTORIAL = "sinsquad.intent.tutorial.v4";
const PHASE: Record<string, string> = {
  draft: "选三个人物",
  place: "人物与数字排位",
  "initial-plan": "设置初始技能",
  plan: "调整技能",
  bet: "下注",
  operate: "装备机会",
  bid: "竞拍场地替换",
  done: "本手结算",
};
const KIND: Record<string, string> = {
  off: "未发动",
  aim: "指向技能",
  reinforce: "强化技能",
  choice: "抉择技能",
  flip: "翻面技能",
};
const ICONS = ["◈", "⌁", "⛨", "◇", "✦", "↗"];
const seed = () => Math.floor(Math.random() * 1e9);
const button = (action: string, text: string, arg = "", disabled = false) =>
  `<button data-ia="${action}" data-arg="${esc(arg)}" ${disabled ? "disabled" : ""}>${esc(text)}</button>`;
const TIPS = [
  [
    "赢两路，拿底池",
    "各位置始终与对面比最终力量，赢的位置更多就赢本手；平局分底池。原数是起点，人物与数字分别排位。9个人物候选可以重名，也可以选两张同名人物。",
  ],
  [
    "技能可跨位置，比较不换位",
    "每个人物恰好一个主动技能，默认关闭。前三轮可调整发动、目标或模式，每轮统一提交一次。对手看到是否发动、类型和指向，看不到人物身份、精确数字及具体模式。双方提交后一起更新；第三轮后全部锁定。基础能力无需发动。",
  ],
  [
    "只留一条场地",
    "开场效果立即生效。前三轮装备后各翻一条候选，同时暗标0–6筹码，选择替换或保留。双方出价都进底池，高价者决定，同价保留旧场地。替换成功，旧效果立即失效；永不叠加。",
  ],
  [
    "装备是承诺",
    "每轮最多一次，共三次机会，可以不买。付2筹码之后必须三选一，装在空位；不能退钱、丢弃或替换。装备没有保底加力，既可能改变技能输出，也可能改道、格挡或延迟收到的效果。",
  ],
  [
    "看输入输出，不用心算过程",
    "每张牌旁会写明支付或收到多少力量、强化或削弱哪个位置，以及装备和场地改变了什么。只讲输入输出，不用追踪中间过程。「本例」是假设敌阵下的演算，不保证实战如此；摊牌后的「本次」才是真实结果。装备与场地的影响分别比较，不能直接相加。",
  ],
  [
    "读信号，再决定投入",
    "对手低中高只代表构成，不代表位置。装备与箭头提供线索，也可能是诱导。无法获胜时可以弃牌；跟注、加注和过牌都有成本。第三轮锁定后不再改牌，第四轮起双方不下注就摊牌；全押也会摊牌。刷新可续玩，筹码延续到下一手。",
  ],
];

export class IntentMode {
  private root = document.createElement("section");
  private session: IntentSession | null = null;
  private worker: Worker | null = null;
  private request = 0;
  private busy = false;
  private style: Style = "cautious";
  private selected: number[] = [];
  private order = [0, 1, 2];
  private numbers = [0, 1, 2];
  private swap: { kind: "unit" | "number"; pos: number } | null = null;
  private draftPlans: Plan[] = [];
  private planKey = "";
  private tutorial = -1;
  private detail: string | null = null;
  private error = "";
  private offer = 0;
  private slot = 0;
  private bidYes = true;
  private amount = 0;
  static hasSave() {
    try {
      return localStorage.getItem(SAVE) !== null;
    } catch {
      return false;
    }
  }
  constructor(private hooks: { exit(): void; art: Set<string> }) {
    this.root.id = "intent-mode";
    document.body.append(this.root);
    this.root.addEventListener("click", (e) => {
      const el = (e.target as HTMLElement).closest<HTMLElement>("[data-ia]");
      if (el && !el.hasAttribute("disabled"))
        this.click(el.dataset.ia!, el.dataset.arg || "");
    });
    this.root.addEventListener("change", (e) => {
      const el = e.target as HTMLSelectElement;
      if (el.dataset.plan !== undefined) {
        this.draftPlans[Number(el.dataset.plan)] = JSON.parse(el.value) as Plan;
        this.persist();
        this.draw();
      }
    });
    this.root.addEventListener("input", (e) => {
      const el = e.target as HTMLInputElement;
      if (el.dataset.amount) {
        this.amount = Number(el.value);
        this.root
          .querySelectorAll("[data-amount-label]")
          .forEach((n) => (n.textContent = el.value));
      }
    });
    this.root.addEventListener("dragstart", (e) => {
      const el = (e.target as HTMLElement).closest<HTMLElement>("[data-swap]");
      if (el) {
        const [kind, pos] = el.dataset.swap!.split(":");
        this.swap = { kind: kind as "unit" | "number", pos: Number(pos) };
        e.dataTransfer?.setData("text/plain", el.dataset.swap!);
      }
    });
    this.root.addEventListener("dragover", (e) => {
      if ((e.target as HTMLElement).closest("[data-position]"))
        e.preventDefault();
    });
    this.root.addEventListener("drop", (e) => {
      const el = (e.target as HTMLElement).closest<HTMLElement>(
        "[data-position]",
      );
      if (el && this.swap) {
        e.preventDefault();
        this.exchange(this.swap.kind, Number(el.dataset.position));
      }
    });
    this.root.addEventListener("keydown", (e) => {
      if (e.key === "Escape" && (this.detail || this.tutorial >= 0)) {
        this.detail = null;
        this.tutorial = -1;
        this.draw();
        return;
      }
      const el = (e.target as HTMLElement).closest<HTMLElement>(
        '[role="button"][data-ia]',
      );
      if (el && (e.key === "Enter" || e.key === " ")) {
        e.preventDefault();
        this.click(el.dataset.ia!, el.dataset.arg || "");
      }
      if (e.key === "Tab" && (this.detail || this.tutorial >= 0)) {
        const focusable = Array.from(
          this.root.querySelectorAll<HTMLElement>(
            '.intent-modal button:not(:disabled),.intent-modal [tabindex="0"]',
          ),
        );
        const first = focusable[0],
          last = focusable.at(-1);
        if (e.shiftKey && document.activeElement === first) {
          e.preventDefault();
          last?.focus();
        } else if (!e.shiftKey && document.activeElement === last) {
          e.preventDefault();
          first?.focus();
        }
      }
    });
  }
  start(style: Style) {
    this.style = style;
    this.session = new IntentSession(seed());
    this.reset();
    try {
      this.tutorial = localStorage.getItem(TUTORIAL) ? -1 : 0;
    } catch {
      this.tutorial = 0;
    }
    this.open();
  }
  resume() {
    try {
      const data = JSON.parse(localStorage.getItem(SAVE) || "null");
      this.session = IntentSession.restore(data.table as IntentSave);
      this.style = data.style;
      this.reset();
      if (
        Array.isArray(data.order) &&
        [...data.order].sort().join() === "0,1,2"
      )
        this.order = data.order;
      if (
        Array.isArray(data.numbers) &&
        [...data.numbers].sort().join() === "0,1,2"
      )
        this.numbers = data.numbers;
      if (
        Array.isArray(data.selected) &&
        new Set(data.selected).size === data.selected.length &&
        data.selected.every(
          (i: number) => Number.isInteger(i) && i >= 0 && i < 9,
        )
      )
        this.selected = data.selected.slice(0, 3);
      const o = this.session.table.observe(0);
      if (
        o.me.units &&
        Array.isArray(data.plans) &&
        data.plans.length === 3 &&
        data.plans.every((p: Plan, i: number) =>
          plans(o.me.units![i].id, i).some(
            (q) => JSON.stringify(q) === JSON.stringify(p),
          ),
        )
      ) {
        this.draftPlans = data.plans;
        this.planKey = `${o.round}:${o.phase}`;
      }
      this.tutorial = -1;
      this.open();
    } catch {
      this.start("cautious");
      this.error = "旧存档无法读取，已开新桌。";
      this.draw();
    }
  }
  private reset() {
    this.worker?.terminate();
    this.worker = null;
    this.request++;
    this.busy = false;
    this.selected = [];
    this.order = [0, 1, 2];
    this.numbers = [0, 1, 2];
    this.draftPlans = [];
    this.planKey = "";
    this.swap = null;
    this.error = "";
    this.detail = null;
    this.offer = 0;
    this.slot = 0;
    this.amount = 0;
  }
  private open() {
    this.root.classList.add("open");
    document.querySelector("#app")?.classList.add("numeric-hidden");
    setScene("bet", "intent-table");
    this.draw();
    this.persist();
    this.runBot();
  }
  private persist() {
    if (!this.session) return;
    try {
      localStorage.setItem(
        SAVE,
        JSON.stringify({
          table: this.session.save(),
          style: this.style,
          order: this.order,
          numbers: this.numbers,
          selected: this.selected,
          plans: this.draftPlans,
        }),
      );
    } catch {
      this.error = "浏览器存储不可用，本局刷新后无法恢复。";
    }
  }
  private exit() {
    this.persist();
    this.reset();
    this.session = null;
    this.root.classList.remove("open");
    this.root.innerHTML = "";
    document.querySelector("#app")?.classList.remove("numeric-hidden");
    this.hooks.exit();
  }
  private act(action: Action) {
    if (!this.session) return;
    try {
      this.session.act(0, action);
      this.error = "";
      this.amount = 0;
      this.persist();
      this.draw();
      this.runBot();
    } catch (e) {
      this.error = String(e);
      this.draw();
    }
  }
  private runBot() {
    if (!this.session || this.busy || !this.session.table.actors().includes(1))
      return;
    try {
      this.worker ??= new Worker(new URL(__INTENT_WORKER__, location.href), {
        type: "module",
      });
      const id = ++this.request;
      this.busy = true;
      this.worker.onmessage = (e) => {
        if (id !== this.request || e.data.id !== id || !this.session) return;
        this.busy = false;
        if (e.data.error) {
          this.error = "对手计算失败，可点重试。";
          this.draw();
          return;
        }
        try {
          this.session.act(1, e.data.action);
          this.persist();
          this.draw();
          this.runBot();
        } catch (error) {
          this.error = String(error);
          this.draw();
        }
      };
      this.worker.onerror = () => {
        this.busy = false;
        this.worker?.terminate();
        this.worker = null;
        this.error = "对手计算未完成，可点重试。";
        this.draw();
      };
      this.worker.postMessage({
        id,
        observation: this.session.table.observe(1),
        style:
          this.style === "aggressive"
            ? "pressure"
            : this.style === "cautious"
              ? "cautious"
              : "balanced",
      });
    } catch (e) {
      this.busy = false;
      this.error = String(e);
      this.draw();
    }
  }
  private exchange(kind: "unit" | "number", pos: number) {
    if (this.session?.table.phase !== "place") return;
    if (this.swap?.kind === kind) {
      const arr = kind === "unit" ? this.order : this.numbers;
      [arr[this.swap.pos], arr[pos]] = [arr[pos], arr[this.swap.pos]];
      this.swap = null;
    } else this.swap = { kind, pos };
    this.persist();
    this.draw();
  }
  private click(type: string, arg: string) {
    const o = this.session?.table.observe(0);
    if (!o) return;
    if (type === "exit") return this.exit();
    if (type === "music") {
      toggleMuted();
      this.draw();
      return;
    }
    if (type === "tutorial") {
      this.tutorial = 0;
      this.draw();
      return;
    }
    if (type === "tut-next") {
      this.tutorial++;
      if (this.tutorial >= TIPS.length) {
        this.tutorial = -1;
        try {
          localStorage.setItem(TUTORIAL, "1");
        } catch {
          /* Private browsing. */
        }
      }
      this.draw();
      return;
    }
    if (type === "tut-back") {
      this.tutorial = Math.max(0, this.tutorial - 1);
      this.draw();
      return;
    }
    if (type === "close") {
      this.detail = null;
      this.tutorial = -1;
      try {
        localStorage.setItem(TUTORIAL, "1");
      } catch {}
      this.draw();
      return;
    }
    if (type === "info") {
      this.detail = arg;
      this.draw();
      return;
    }
    if (type === "retry") {
      this.error = "";
      this.runBot();
      return;
    }
    if (type === "next") {
      this.session = this.session!.next(seed());
      this.reset();
      this.persist();
      this.draw();
      this.runBot();
      return;
    }
    if (type === "select") {
      const i = Number(arg);
      this.selected = this.selected.includes(i)
        ? this.selected.filter((x) => x !== i)
        : this.selected.length < 3
          ? [...this.selected, i]
          : this.selected;
      this.persist();
      this.draw();
      return;
    }
    if (type === "swap") {
      const [kind, p] = arg.split(":");
      return this.exchange(kind as "unit" | "number", Number(p));
    }
    if (type === "offer") {
      this.offer = Number(arg);
      this.draw();
      return;
    }
    if (type === "slot") {
      this.slot = Number(arg);
      this.draw();
      return;
    }
    if (type === "stance") {
      this.bidYes = arg === "yes";
      this.draw();
      return;
    }
    if (type === "draft")
      return this.act({ type: "draft", indices: this.selected });
    if (type === "redraw") {
      this.selected = [];
      return this.act({ type: "redraw" });
    }
    if (type === "place")
      return this.act({
        type: "place",
        units: this.order,
        numbers: this.numbers,
      });
    if (type === "plan")
      return this.act({ type: "plan", plans: this.draftPlans });
    if (type === "buy") return this.act({ type: "operate", buy: true });
    if (type === "skip") return this.act({ type: "operate", buy: false });
    if (type === "equip")
      return this.act({ type: "equip", offer: this.offer, pos: this.slot });
    if (type === "bid")
      return this.act({ type: "bid", yes: this.bidYes, amount: this.amount });
    if (type === "raise") {
      const all = o.stacks[0] + o.bet.paid[0];
      return this.act({
        type: "raise",
        to: Math.min(all, Math.max(o.bet.min, this.amount)),
      });
    }
    if (["check", "call", "fold"].includes(type))
      return this.act({ type: type as "check" | "call" | "fold" });
  }
  private physical(
    u: Unit | null,
    p: number,
    seat: 0 | 1,
    o: Observation,
    offerIndex?: number,
  ) {
    const c = u ? card(u.id) : null;
    const a = u ? cardArt(u.id) : "";
    const sin = c ? sinOf(c.id).name : null;
    const oldSin = sin === "暴怒" ? "愤怒" : sin;
    const color = oldSin
      ? SIN_COLOR[oldSin as keyof typeof SIN_COLOR]
      : "var(--gold)";
    const latin = oldSin ? SIN_LATIN[oldSin as keyof typeof SIN_LATIN] : "";
    const equipment = u?.gear ?? (seat === 1 ? o.foe.equipment[p] : null);
    const placing =
      seat === 0 && o.phase === "place" && offerIndex === undefined;
    const attrs =
      offerIndex !== undefined
        ? `data-ia="select" data-arg="${offerIndex}" role="button" tabindex="0" aria-label="选择候选${offerIndex + 1} ${c!.name}"`
        : placing
          ? `data-ia="swap" data-arg="unit:${p}" data-swap="unit:${p}" draggable="true" role="button" tabindex="0" aria-label="交换${p + 1}位人物"`
          : "";
    const power = o.result?.battle?.powers[seat][p];
    const front = c
      ? `<div class="art ${this.hooks.art.has(a) ? "has-portrait" : ""}"><span class="glyph">${latin}</span>${this.hooks.art.has(a) ? `<img class="portrait" src="art/${a}.webp" alt="" draggable="false">` : ""}<i class="varnish"></i></div><i class="orn"></i><span class="sin-tag">${latin}</span><div class="plate"><span>${esc(c.name)}</span></div><div class="text">${esc(c.uses[0])}</div><div class="stats"><span>${c.basic ? { shield: "护幕", reserve: "蓄能", relay: "接力" }[c.basic] : c.grade}</span><span class="stat atk">${offerIndex !== undefined ? "✦" : (power ?? u!.raw)}</span><span>${power !== undefined ? "原" + u!.raw : offerIndex !== undefined ? c.grade : "原数"}</span></div><button class="info-btn" data-ia="info" data-arg="${c.id}" aria-label="${esc(c.name)}完整规则">?</button><i class="linen"></i><i class="sheen"></i><i class="gloss"></i>`
      : "";
    return cardShell({
      classes: `card person fr-${currentFrame()} foil intent-card ${!u ? "down" : ""} ${offerIndex !== undefined && this.selected.includes(offerIndex) ? "selected" : ""} ${placing && this.swap?.kind === "unit" && this.swap.pos === p ? "selected" : ""}`,
      attributes: `style="--sin:${color}" ${attrs}`,
      front,
      back: equipment
        ? `<span class="intent-back-gear">${esc(gear(equipment).name)}</span>`
        : "",
    });
  }
  private gearBadge(id: string | null) {
    return id
      ? `<button class="intent-gear" data-ia="info" data-arg="${id}"><span aria-hidden="true">${ICONS[Number(id.slice(1)) % ICONS.length]}</span> ${esc(gear(id).name)}</button>`
      : '<span class="intent-empty" aria-label="装备空位">◇</span>';
  }
  private draw() {
    if (!this.session) return;
    const o = this.session.table.observe(0),
      editable =
        ["initial-plan", "plan"].includes(o.phase) && o.actor.includes(0);
    const key = `${o.round}:${o.phase}`;
    if (this.planKey !== key) {
      this.planKey = key;
      this.draftPlans = o.me.units?.map((u) => structuredClone(u.plan)) ?? [];
      this.amount = 0;
      this.offer = 0;
      this.slot = Math.max(0, o.me.units?.findIndex((u) => !u.gear) ?? 0);
    }
    const own =
      o.me.units?.map((u, p) => ({
        ...u,
        plan: ["initial-plan", "plan"].includes(o.phase)
          ? this.draftPlans[p]
          : u.plan,
      })) ??
      (o.phase === "place"
        ? this.order.map((i, p) => ({
            id: o.me.kept[i],
            raw: o.me.numbers[this.numbers[p]],
            gear: null,
            plan: OFF(),
          }))
        : null);
    let analysis: ReturnType<typeof analyse> = null;
    try {
      analysis = analyse(o, own ?? undefined);
    } catch {
      this.error = "此配置的分析暂不可用；不会显示不可靠结果。";
    }
    const field = o.effects.find((f) => f.active),
      fieldCard = FIELDS.find((f) => f.id === field?.id)!;
    const foe = o.result?.teams?.[1];
    const enemyAnalysis = foe ? analyse(this.session.table.observe(1)) : null;
    const enemyCards = [0, 1, 2]
      .map(
        (p) =>
          `<div class="intent-position foe" data-position="${p}">${this.physical(foe?.[p] ?? null, p, 1, o)}${this.gearBadge(o.foe.equipment[p])}<p class="intent-arrow">${foe ? esc(planText(foe[p].id, foe[p].plan, true)) : this.signal(o, p)}</p><p class="intent-analysis">${esc(enemyAnalysis ? compactAnalysis(enemyAnalysis, p) : publicAnalysis(o, p))}</p></div>`,
      )
      .join("");
    const myCards =
      own
        ?.map(
          (u, p) =>
            `<div class="intent-position own" data-position="${p}">${this.physical(u, p, 0, o)}<div class="intent-side">${this.gearBadge(u.gear)}${o.phase === "place" ? button("swap", `数字 ${u.raw} ↔`, `number:${p}`) : ""}<div class="intent-arrow">${esc(planText(u.id, u.plan))}</div>${editable ? this.planControl(u, p) : ""}${analysis ? `<p class="intent-analysis" aria-label="${esc(card(u.id).name)}输入输出分析">${esc(compactAnalysis(analysis, p))}</p>` : ""}</div></div>`,
        )
        .join("") ??
      `<div class="intent-hand-numbers">${o.me.numbers.map((n) => `<b>${n}</b>`).join("")}<span>你的三个原始数字</span></div>`;
    this.root.innerHTML = `<div class="room intent-room" style="--room:url('room/A01.webp')"></div><header class="intent-top"><b>七罪 · 暗流</b><span>第${this.session.hand}手 · ${o.round <= 3 ? `第${o.round}轮` : "配置锁定"} · ${o.initiative === 0 ? "你" : "对手"}先结算</span><strong>你 ${o.stacks[0]} ｜ 对手 ${o.stacks[1]}</strong>${button("music", isMuted() ? "♪ 关" : "♪ 开")}${button("tutorial", "教程")}${button("exit", "退出")}</header><section class="intent-field"><button data-ia="info" data-arg="${fieldCard.id}"><small>当前唯一场地</small><b>${esc(fieldCard.name)}</b><span>${esc(fieldCard.text)}</span></button><small>新候选 ${Math.min(o.effects.filter((f) => f.id !== null).length - 1, 3)}/3</small></section><main class="intent-board numeric-board"><div class="intent-composition">对手构成 ${o.foe.tiers.map((n) => ["低", "中", "高"][n]).join(" · ")} <small>不对应位置</small></div><section class="intent-row enemy">${enemyCards}</section><div class="intent-center"><span>${PHASE[o.phase]}</span><strong>◉ ${o.pot}</strong></div><section class="intent-row mine">${myCards}</section>${analysis ? `<aside class="intent-analysis-key">${analysis.kind === "actual" ? "本次＝摊牌实算" : "本例＝假设敌阵下的演算，并非真实暗牌"} · ${button("info", "分析怎么看", "analysis")}</aside>` : ""}${o.phase === "draft" ? `<div class="intent-draft">${o.me.offer.map((id, i) => this.physical({ id, raw: 0, gear: null, plan: OFF() }, i, 0, o, i)).join("")}</div>` : ""}</main><footer class="intent-dock">${this.error ? `<p role="alert">${esc(this.error)} ${button("retry", "重试")}</p>` : ""}${this.dock(o)}</footer>${this.tutorial >= 0 ? this.tutorialView() : this.detail ? this.detailView(o, analysis) : ""}`;
    if (this.detail || this.tutorial >= 0) {
      for (const el of Array.from(this.root.children))
        if (el instanceof HTMLElement && !el.classList.contains("intent-modal"))
          el.inert = true;
      this.root
        .querySelector<HTMLButtonElement>(".intent-modal button:not(:disabled)")
        ?.focus();
    }
    relight();
  }
  private signal(o: Observation, p: number) {
    const s = o.foe.signals[p];
    return s
      ? `${KIND[s.kind]}${s.targets.length ? " → " + s.targets.map((t) => `${t.side === "ally" ? "敌" : "己"}${t.pos + 1}位`).join(" / ") : ""}`
      : "◇";
  }
  private planControl(u: Unit, p: number) {
    return `<label class="intent-plan">技能<select data-plan="${p}" aria-label="${p + 1}位技能设置">${plans(
      u.id,
      p,
    )
      .map(
        (plan) =>
          `<option value="${esc(JSON.stringify(plan))}" ${JSON.stringify(plan) === JSON.stringify(u.plan) ? "selected" : ""}>${esc(planText(u.id, plan))}</option>`,
      )
      .join("")}</select></label>`;
  }
  private dock(o: Observation): string {
    if (o.result) {
      const r = o.result;
      return `<strong>${r.winner === null ? "平局" : r.winner === 0 ? "你赢了" : "对手获胜"}${r.fold ? " · 弃牌结算" : ""}</strong><span>本手发放：你 ${r.payouts[0]}，对手 ${r.payouts[1]}</span>${r.battle ? `<span>左 ${r.battle.powers[0][0]}:${r.battle.powers[1][0]}　中 ${r.battle.powers[0][1]}:${r.battle.powers[1][1]}　右 ${r.battle.powers[0][2]}:${r.battle.powers[1][2]}</span>` : ""}${o.stacks.every((n) => n > 0) ? button("next", "下一手") : button("exit", "本桌结束 · 返回")}`;
    }
    if (!o.actor.includes(0))
      return `<span class="intent-wait">等待对手提交…</span>`;
    if (o.phase === "draft")
      return `<span>选中 ${this.selected.length}/3 · 允许同名</span>${button("redraw", "换一批", "", o.me.redrawn)}${button("draft", "确认三人", "", this.selected.length !== 3)}`;
    if (o.phase === "place")
      return `<span>${this.swap ? "再点目标位置完成交换" : "点两张人物交换；点两个数字交换。也可拖动人物。"}</span>${button("place", "确认排位")}`;
    if (o.phase.includes("plan"))
      return `<span>修改仅本地可见，双方提交后一起更新指向。${o.round === 3 ? "本次提交后锁定。" : ""}</span>${button("plan", "确认技能")}`;
    if (o.phase === "operate") {
      if (o.me.gearOffers.length)
        return `<div class="intent-equipment-options">${o.me.gearOffers.map((id, i) => `<button class="${i === this.offer ? "chosen" : ""}" data-ia="offer" data-arg="${i}"><b>${esc(gear(id).name)}</b><span>${esc(gear(id).text)}</span></button>`).join("")}</div><div class="intent-install">${o.me.units!.map((u, p) => button("slot", `${this.slot === p ? "●" : "○"} ${p + 1}位`, String(p), !!u.gear)).join("")}${button("equip", "安装所选装备", "", !!o.me.units![this.slot].gear)}</div>`;
      return `<span>装备机会 ${o.round}/3 · 付费后必须三选一安装</span>${button("buy", "付2筹码选装备", "", o.stacks[0] <= 2 || o.me.units!.every((u) => !!u.gear))}${button("skip", "本轮不拿")}`;
    }
    if (o.phase === "bid") {
      const f = FIELDS.find((f) => f.id === o.effects[o.round].id)!;
      const max = Math.max(0, Math.min(6, Math.floor(o.stacks[0] - 1)));
      return `<div><b>候选：${esc(f.name)}</b><span>${esc(f.text)}</span></div>${button("stance", `${this.bidYes ? "●" : "○"} 替换`, "yes")}${button("stance", `${!this.bidYes ? "●" : "○"} 保留`, "no")}<label>暗标 <input type="range" data-amount="bid" min="0" max="${max}" step="1" value="${this.amount}"><b data-amount-label>${this.amount}</b></label>${button("bid", "提交暗标")}<small>双方出价进底池，同价保留当前场地。</small>`;
    }
    if (o.phase === "bet") {
      const all = o.stacks[0] + o.bet.paid[0],
        min = Math.min(o.bet.min, all);
      return `${button("fold", "弃牌")}${o.bet.call ? button("call", `跟注 ${Math.min(o.bet.call, o.stacks[0])}`) : button("check", "过牌")}<label>加至 <input type="range" data-amount="raise" min="${min}" max="${Math.max(min, all)}" step="0.5" value="${Math.max(min, this.amount)}"><b data-amount-label>${Math.max(min, this.amount)}</b></label>${button("raise", all < o.bet.min ? "全押" : "下注 / 加注", "", all <= o.bet.target || o.stacks[1] === 0)}`;
    }
    return "";
  }
  private tutorialView() {
    const [title, text] = TIPS[this.tutorial];
    return this.modal(
      `<small>教程 ${this.tutorial + 1}/${TIPS.length}</small><h2>${title}</h2><p>${text}</p><div>${button("tut-back", "上一页", "", this.tutorial === 0)}${button("tut-next", this.tutorial === TIPS.length - 1 ? "开始玩" : "下一页")}${button("close", "跳过")}</div>`,
    );
  }
  private detailView(o: Observation, a: ReturnType<typeof analyse>) {
    if (this.detail === "analysis")
      return this.modal(
        `<h2>只看输入与输出</h2><p>${esc(a?.assumption ?? "选好人物并排位后显示分析。")}</p><p>说明包含人物能力、主动技能、装备和场地共同产生的结果。左、中、右均按牌桌位置描述；己方说明中的队友是己方，敌方说明中的队友是敌方。不会展开中间触发过程。</p><p>例如「聚焦镜使中位多3点力量」，指保留同一敌阵及其余配置，相比不装聚焦镜，中位最终多3点力量。场地也单独这样比较，两者不能直接相加。「没有改变最终力量」可能是没有触发，也可能是收益与代价互相抵消。</p>${
          a
            ? `<p>${a.kind === "actual" ? "实际敌阵" : "示例1假设敌阵"}：${a.example
                .map(
                  (u, p) =>
                    `${p + 1}位${card(u.id).name}·${u.raw}·${planText(u.id, u.plan, true)}`,
                )
                .map(esc)
                .join("；")}</p>`
            : ""
        }${button("close", "关闭")}`,
      );
    const id = this.detail!;
    let title = "",
      text = "";
    if (/^G\d/.test(id)) {
      const g = gear(id);
      title = g.name;
      text = g.text;
    } else if (/^F\d/.test(id)) {
      const f = FIELDS.find((f) => f.id === id)!;
      title = f.name;
      text = f.text;
    } else {
      const c = card(id);
      title = `${c.name} · ${sinOf(id).name}`;
      text = c.text + (c.basic ? " " + BASIC_TEXT[c.basic] : "");
    }
    return this.modal(
      `<h2>${esc(title)}</h2><p>${esc(text)}</p>${button("close", "关闭")}`,
    );
  }
  private modal(body: string) {
    return `<div class="intent-modal"><section role="dialog" aria-modal="true" aria-label="规则与教程">${body}</section></div>`;
  }
}
