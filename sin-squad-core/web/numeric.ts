import { cardShell } from "./card-shell.js";
import { KEYWORDS } from "../src/numeric/keywords.js";
import type { Style } from "../src/ai/agents.js";
import type {
  NumericAction,
  NumericObservation,
} from "../src/numeric/types.js";
import { character } from "../src/content/characters.js";
import {
  characterById,
  equipmentById,
  arenaById,
  ruleById,
  effectById,
  NUMERIC_SETTLEMENT_TEXT,
  type NumericEquipmentTier,
} from "../src/numeric/content.js";
import { esc, SIN_COLOR } from "./text.js";
import { cardArt } from "./campaign.js";
import { currentFrame } from "./frames.js";
import { reducedMotion } from "./motion.js";
import { morph } from "./morph.js";
import { relight } from "./light.js";
import { SIN_LATIN } from "./sigil.js";
import { isMuted, toggleMuted, setScene } from "./music.js";

/**
 * 独立的单数值牌桌界面。它只依赖 NumericTable 的观察层和动作入口，
 * 不读取旧 Table 的内部状态，因此可以和朋友的战役、自由牌桌并存。
 */
export interface NumericTableLike {
  save?(): unknown;
  observe(seat: 0 | 1): NumericObservation;
  apply(seat: 0 | 1, action: NumericAction): void;
  aiAction?(seat: 1, style: Style): NumericAction | null;
}

export interface NumericModeHooks {
  restore(data: unknown): NumericTableLike;
  create(style: Style): NumericTableLike;
  exit(): void;
  art: Set<string>;
}

const TUTORIAL_KEY = "sinsquad.numeric.tutorial.v3";
const SAVE_KEY = "sinsquad.numeric.save.v2";
const readTutorial = () => {
  try {
    return localStorage.getItem(TUTORIAL_KEY) === "1";
  } catch {
    return false;
  }
};
const saveTutorial = () => {
  try {
    localStorage.setItem(TUTORIAL_KEY, "1");
  } catch {
    /* 无痕模式不影响游玩 */
  }
};

const styleName: Record<Style, string> = {
  cautious: "谨慎的税官",
  aggressive: "激进的挑衅者",
  bluff: "爱诈唬的魅惑者",
};
const phaseName: Record<string, string> = {
  draft: "选三个人物 / 可换一批",
  place: "数字与效果排位",
  bet: "下注",
  operate: "操作费与装备",
  equip: "安装装备",
  vote: "场地效果表决",
  bid: "场地效果暗标",
  result: "结算",
  over: "牌桌结束",
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
function lookUp<T extends { id: string; name: string; text: string }>(
  fn: (id: string) => T,
  id: string,
): T {
  try {
    return fn(id);
  } catch {
    return { id, name: id, text: "该环境效果的详细文本将在揭示时显示" } as T;
  }
}

export class NumericMode {
  static hasSave() {
    try {
      return localStorage.getItem(SAVE_KEY) !== null;
    } catch {
      return false;
    }
  }
  resume() {
    try {
      const data = JSON.parse(localStorage.getItem(SAVE_KEY) ?? "null");
      if (!data || !["cautious", "aggressive", "bluff"].includes(data.style))
        throw Error("存档格式不兼容");
      this.start(data.style, this.hooks.restore(data.table));
      if (
        [data.effects, data.numbers].every(
          (xs) =>
            Array.isArray(xs) &&
            xs.length === 3 &&
            new Set(xs).size === 3 &&
            xs.every((x: number) => Number.isInteger(x) && x >= 0 && x < 3),
        )
      ) {
        this.selectedEffects = data.effects;
        this.selectedNumbers = data.numbers;
        this.draw();
        this.persist();
      }
    } catch {
      this.start("cautious");
      this.error = "原存档无法读取，已开始新桌。";
      this.draw();
    }
  }
  private persist() {
    if (!this.table?.save) return;
    try {
      if (this.obs()?.phase === "over") localStorage.removeItem(SAVE_KEY);
      else
        localStorage.setItem(
          SAVE_KEY,
          JSON.stringify({
            style: this.style,
            table: this.table.save(),
            effects: this.selectedEffects,
            numbers: this.selectedNumbers,
          }),
        );
    } catch {
      this.error = "浏览器无法保存进度，请勿刷新或关闭本局。";
    }
  }
  private readonly root: HTMLElement;
  private table: NumericTableLike | null = null;
  private style: Style = "cautious";
  private tutorialOpen = !readTutorial();
  private tutorialPage = 0;
  private error = "";
  private amount = 5;
  private swap: { kind: "e" | "n"; pos: number } | null = null;
  private dragging: { kind: "e" | "n"; pos: number } | null = null;
  private touchDrag: {
    kind: "e" | "n";
    pos: number;
    x: number;
    y: number;
  } | null = null;
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
    [
      "先记住这一个目标",
      "赢筹码。每手双方先放 2 枚底注进奖池，再组队、下注、比大小；不足 2 枚时双方按较少的一方交底注。赢家拿走奖池，平局平分，单出的 1 枚给本手庄家（每手轮换）。结算后重新发牌，直到一方筹码归零。",
    ],
    [
      "先挑人物，再搭配数字",
      "你会拿到 3 个数字（3～10），它们不能重抽。先看场地与胜利规则，再从 9 张人物中点选 3 张。候选可重复，同名人物可以一起上场。想换候选时，可先保留 0～2 个再点“换一批”：已选的不变，未选的换走，新一批仍可能出现同名人物，每手只能换一次。点选即保留，选满 3 个后进入排位。",
    ],
    [
      "三个位置，各比各的",
      "把 3 个人物与 3 张数字自由搭配；拖动牌换人物，拖动徽章换数字；也可分别点选两项交换。重复数字也算不同的两张牌。锁定前可调整，锁定后不可改。1号位对1号位，2对2，3对3。最终胜负看本手的胜利规则，不一定是总和更大就赢。点卡牌详情可看条件。",
    ],
    [
      "每轮只做眼前的决定",
      "先下注：不想加钱就过牌；对手下注后可跟注、加注或弃牌。下注最少 2 枚；加注填写本轮总额，例如已投 5、加到 8，就是再付 3。筹码不足可全押；对手跟注后立即开战，无法匹配的多余下注退回。弃牌则让对手拿走奖池。",
    ],
    [
      "装备与额外效果，到时再选",
      "下注跟齐后可跳过装备，或付 2 枚看三选一（不足 2 枚付剩余筹码）；看过再放弃也不退费。双方决定完才一起公开装备。前三轮只能装空位，第4～7轮可以替换。前三轮各表决一张额外效果；意见不同才暗标，现场会显示出价上限和规则。",
    ],
    [
      "关键词与装备线索",
      "所有装备都有基础力量；满足条件或触发关键词会更强。蓄能器接受自身、队友及装备增益，截流夺取对位强化，护盾挡一次敌方控制或减力。沉默只关闭人物（遗赠除外），封印只关闭装备。看见装备只能推测打法，不能确定人物；锁阵后读出劣势，可以弃牌止损。详情和下方词典随时可查。",
    ],
    [
      "什么时候比大小？",
      "前三轮要处理完额外效果。从第4轮起，双方整轮都没追加筹码、没付装备费，就开战；第7轮后只剩下注。有人把剩余筹码用完时，在当前必要的跟注或装备决定完成后开战，未表决的效果关闭。开战后公开双方牌面与计算明细。无需背完：每个阶段都有提示，随时点“教程”重看。",
    ],
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
      if (
        !el ||
        el.classList.contains("disabled") ||
        el.hasAttribute("disabled")
      )
        return;
      this.onAction(el.dataset.nact!, el.dataset.arg);
    });
    this.root.addEventListener("dragstart", (ev) => {
      const el = (ev.target as HTMLElement).closest<HTMLElement>("[data-drag]");
      if (
        !el ||
        this.obs()?.phase !== "place" ||
        !this.obs()?.toAct.includes(0) ||
        this.tutorialOpen ||
        this.detail
      )
        return ev.preventDefault();
      this.dragging = {
        kind: el.dataset.drag as "e" | "n",
        pos: Number(el.dataset.pos),
      };
      ev.dataTransfer?.setData("text/plain", "numeric-placement");
    });
    this.root.addEventListener("dragover", (ev) => {
      if (this.dragging && (ev.target as HTMLElement).closest("[data-own-pos]"))
        ev.preventDefault();
    });
    this.root.addEventListener("drop", (ev) => {
      const el = (ev.target as HTMLElement).closest<HTMLElement>(
        "[data-own-pos]",
      );
      if (!el || !this.dragging) return;
      ev.preventDefault();
      this.swap = this.dragging;
      this.dragging = null;
      this.swapPosition(this.swap.kind, Number(el.dataset.ownPos));
    });
    this.root.addEventListener("dragend", () => {
      this.dragging = null;
    });
    this.root.addEventListener("pointerdown", (ev) => {
      const el = (ev.target as HTMLElement).closest<HTMLElement>("[data-drag]");
      if (ev.pointerType === "touch" && el && this.obs()?.phase === "place")
        this.touchDrag = {
          kind: el.dataset.drag as "e" | "n",
          pos: Number(el.dataset.pos),
          x: ev.clientX,
          y: ev.clientY,
        };
    });
    this.root.addEventListener("pointerup", (ev) => {
      const from = this.touchDrag;
      this.touchDrag = null;
      if (!from || Math.hypot(ev.clientX - from.x, ev.clientY - from.y) < 12)
        return;
      const to = document
        .elementFromPoint(ev.clientX, ev.clientY)
        ?.closest<HTMLElement>("[data-own-pos]");
      if (to) {
        ev.preventDefault();
        this.swap = from;
        this.swapPosition(from.kind, Number(to.dataset.ownPos));
      }
    });
    this.root.addEventListener("pointercancel", () => {
      this.touchDrag = null;
    });
    this.root.addEventListener("input", (ev) => {
      const el = ev.target as HTMLInputElement;
      if (el.dataset.ninput === "amount") {
        this.amount = Math.max(0, Math.floor(Number(el.value) || 0));
        this.root
          .querySelectorAll<HTMLElement>("[data-amount]")
          .forEach((x) => {
            x.textContent = String(this.amount);
          });
      }
    });
    this.root.addEventListener("change", (ev) => {
      const el = ev.target as HTMLSelectElement;
      const i = Number(el.dataset.index);
      if (!Number.isInteger(i) || i < 0 || i > 2) return;
      const mapping =
        el.dataset.nselect === "e"
          ? this.selectedEffects
          : el.dataset.nselect === "n"
            ? this.selectedNumbers
            : null;
      if (!mapping) return;
      const picked = Number(el.value),
        at = mapping.indexOf(picked);
      [mapping[i], mapping[at]] = [mapping[at], mapping[i]];
      this.persist();
      this.draw();
    });
    this.root.addEventListener("keydown", (ev) => {
      if (ev.key === "Escape" && this.detail) {
        this.detail = null;
        return this.draw();
      }
      const el = (ev.target as HTMLElement).closest<HTMLElement>("[data-nact]");
      if (
        (ev.key === "Enter" || ev.key === " ") &&
        el?.getAttribute("role") === "button"
      ) {
        ev.preventDefault();
        this.onAction(el.dataset.nact!, el.dataset.arg);
      }
    });
    this.root.addEventListener("pointermove", (ev) => {
      const el = (ev.target as HTMLElement).closest<HTMLElement>(
        "[data-ntitle]",
      );
      if (!el || this.tutorialOpen || this.detail) {
        this.hover.style.display = "none";
        return;
      }
      this.hover.innerHTML = `<b>${esc(el.dataset.ntitle ?? "")}</b><p>${esc(el.dataset.ntext ?? "")}</p>`;
      this.hover.style.display = "block";
      const w = this.hover.offsetWidth,
        h = this.hover.offsetHeight;
      this.hover.style.left = `${Math.min(Math.max(8, ev.clientX + 14), window.innerWidth - w - 8)}px`;
      this.hover.style.top = `${Math.min(Math.max(8, ev.clientY + 18), window.innerHeight - h - 8)}px`;
    });
    this.root.addEventListener("pointerleave", () => {
      this.hover.style.display = "none";
    });
    document.body.appendChild(this.root);
  }

  start(style: Style, restored?: NumericTableLike) {
    if (this.aiTimer !== null) window.clearTimeout(this.aiTimer);
    this.aiTimer = null;
    this.style = style;
    this.table = restored ?? this.hooks.create(style);
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
    this.persist();
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
    document
      .querySelector<HTMLElement>("#app")
      ?.classList.remove("numeric-hidden");
    this.hooks.exit();
  }

  private obs(): NumericObservation | null {
    return this.table?.observe(0) ?? null;
  }
  private runAi() {
    if (!this.table || this.tutorialOpen || this.aiTimer !== null) return;
    const o = this.obs();
    if (
      !o ||
      o.phase === "over" ||
      o.phase === "result" ||
      !this.table.aiAction ||
      !o.toAct.includes(1)
    )
      return;
    this.aiTimer = window.setTimeout(
      () => {
        this.aiTimer = null;
        if (!this.table || this.tutorialOpen) return;
        try {
          if (this.table.observe(0).toAct.includes(1)) {
            const a = this.table.aiAction?.(1, this.style);
            if (a) {
              this.table.apply(1, a);
              this.persist();
            }
          }
        } catch (e) {
          this.error = e instanceof Error ? e.message : String(e);
        }
        this.draw();
        this.runAi();
      },
      reducedMotion() ? 40 : 260,
    );
  }

  private send(action: NumericAction) {
    if (!this.table || !this.obs()?.toAct.includes(0)) return;
    try {
      this.table.apply(0, action);
      this.error = "";
      this.draw();
      this.persist();
      this.runAi();
    } catch (e) {
      this.error = e instanceof Error ? e.message : String(e);
      this.draw();
    }
  }

  private onAction(type: string, arg?: string) {
    if (type === "exit") return this.exit();
    if (type === "tutorial") {
      this.tutorialOpen = true;
      this.tutorialPage = 0;
      return this.draw();
    }
    if (type === "tutorialNext") {
      if (this.tutorialPage + 1 >= this.tutorial.length) {
        this.tutorialOpen = false;
        saveTutorial();
      } else this.tutorialPage++;
      this.draw();
      this.runAi();
      return;
    }
    if (type === "tutorialSkip") {
      this.tutorialOpen = false;
      saveTutorial();
      this.draw();
      this.runAi();
      return;
    }
    if (type === "tutorialPrev") {
      this.tutorialPage = Math.max(0, this.tutorialPage - 1);
      return this.draw();
    }
    if (type === "music") {
      toggleMuted();
      return this.draw();
    }
    if (type === "info") {
      const el = this.root.querySelector<HTMLElement>(`[data-info="${arg}"]`);
      if (el)
        this.detail = {
          title: el.dataset.ntitle ?? "详情",
          text: el.dataset.ntext ?? "",
        };
      return this.draw();
    }
    if (type === "closeInfo") {
      this.detail = null;
      return this.draw();
    }
    if (this.tutorialOpen || this.detail) return;
    if (type === "replay") {
      this.outcomeHand = -1;
      return this.draw();
    }
    if (type === "keep" || type === "reroll")
      return this.send(
        type === "keep" ? { type, index: Number(arg) } : { type },
      );
    if (type === "swap") {
      const [kind, pos] = (arg ?? "e,0").split(",");
      return this.swapPosition(kind as "e" | "n", Number(pos));
    }
    if (type === "place")
      return this.send({
        type,
        effects: this.selectedEffects as [number, number, number],
        numbers: this.selectedNumbers as [number, number, number],
      });
    if (type === "bet") return this.send({ type: "bet", amount: this.amount });
    if (type === "raise") return this.send({ type: "raise", to: this.amount });
    if (type === "bid") return this.send({ type: "bid", amount: this.amount });
    if (type === "equip") {
      const [offerIndex, pos] = (arg ?? "0,0").split(",").map(Number);
      return this.send({ type: "equip", offerIndex, pos });
    }
    if (type === "operate")
      return this.send({ type: "operate", draft: arg === "1" });
    if (type === "vote")
      return this.send({ type: "vote", activate: arg === "1" });
    if (type === "next") return this.send({ type: "nextHand" });
    if (["check", "call", "allIn", "fold"].includes(type))
      return this.send({ type } as NumericAction);
  }

  private swapPosition(kind: "e" | "n", pos: number) {
    const o = this.obs();
    if (
      o?.phase !== "place" ||
      !o.toAct.includes(0) ||
      pos < 0 ||
      pos > 2 ||
      this.tutorialOpen ||
      this.detail
    )
      return;
    if (this.swap?.kind === kind) {
      const xs = kind === "e" ? this.selectedEffects : this.selectedNumbers;
      [xs[pos], xs[this.swap.pos]] = [xs[this.swap.pos], xs[pos]];
      this.swap = null;
    } else this.swap = { kind, pos };
    this.draw();
    this.persist();
  }
  private draw() {
    const o = this.obs();
    this.root.classList.add("open");
    if (!o) {
      this.root.innerHTML = "";
      return;
    }
    if (this.layoutHand !== o.handNo) {
      this.layoutHand = o.handNo;
      this.swap = null;
      this.selectedEffects = [0, 1, 2];
      this.selectedNumbers = [0, 1, 2];
      this.replayLine = -1;
      this.replayToken++;
      this.replaying = false;
      this.amount = 5;
    }
    if (o.phase === "bet")
      this.amount = Math.min(
        o.betting.roundBet[0] + o.stacks[0],
        Math.max(o.betting.minRaiseTo, this.amount),
      );
    if (o.phase === "bid") this.amount = Math.min(o.bidCap, this.amount);
    morph(
      this.root,
      `<div class="room numeric-room" style="--room:url('room/A${o.arenaId?.slice(-2) ?? "01"}.webp')"></div>${this.header(o)}${this.environment(o)}${this.board(o)}${this.error ? `<p class="numeric-error" role="alert">${esc(this.error)}</p>` : ""}${this.dock(o)}${this.tutorialOpen ? this.tutorialView() : ""}${this.detail ? `<div class="numeric-tutorial"><div class="numeric-tutorial-panel" role="dialog" aria-modal="true"><h2>${esc(this.detail.title)}</h2><p>${esc(this.detail.text)}</p><button data-nact="closeInfo">关闭详情</button></div></div>` : ""}`,
    );
    this.hover.style.display = "none";
    this.root.dataset.phase = o.phase;
    relight();
    if (o.result?.teams && this.outcomeHand !== o.handNo && !this.replaying)
      void this.playComparison(o);
  }

  private header(o: NumericObservation) {
    return `<header class="numeric-top"><b>七宗罪-德州战棋</b><span>第 ${o.handNo} 手 · 第 ${o.round} 轮 · ${styleName[this.style]}</span><span class="numeric-stacks">你 ${o.stacks[0]} · 对手 ${o.stacks[1]} · 奖池 ${o.pot}</span><button data-nact="music">♪ ${isMuted() ? "关" : "开"}</button><button data-nact="tutorial">教程</button><button data-nact="exit">返回主菜单</button></header>`;
  }

  private environment(o: NumericObservation) {
    const arena = arenaById(o.arenaId!),
      rule = ruleById(o.ruleId!);
    const tile = (
      id: string,
      name: string,
      text: string,
      kind: string,
      status = "",
    ) =>
      `<button class="numeric-env-card ${status}" data-nact="info" data-arg="${id}" data-info="${id}" data-ntitle="${esc(name)}" data-ntext="${esc(text)}" aria-label="${esc(kind + " " + name + (status ? " " + ({ active: "已启用", inactive: "未启用", pending: "待定" }[status] ?? "") : ""))}"><small>${kind}</small><b>${esc(name)}</b><i aria-hidden="true"></i></button>`;
    return `<section class="numeric-environment">${tile("arena", arena.name, arena.text, "场地")}${tile("rule", rule.name, rule.text, "胜利规则")}<div class="numeric-effect-rail">${o.effects
      .map((x, i) => {
        const d = effectById(x.id);
        return tile("fx" + i, d.name, d.text, "效果 " + (i + 1), x.status);
      })
      .join("")}</div></section>`;
  }

  private board(o: NumericObservation) {
    const revealed = o.result?.teams;
    const foe = [0, 1, 2]
      .map((i) => this.slotCard(revealed?.[1]?.[i] ?? null, i, 1, o))
      .join("");
    const prepared =
      o.phase === "place" && o.me.kept.length === 3
        ? this.selectedEffects.map((e, i) => ({
            effectId: o.me.kept[e],
            number: o.me.numbers[this.selectedNumbers[i]],
          }))
        : null;
    const mine =
      (revealed?.[0] ?? o.me.slots ?? prepared)
        ?.map((x, i) => this.slotCard(x, i, 0, o))
        .join("") ??
      `<div class="numeric-numbers">${o.me.numbers.map((n) => `<b>${n}</b>`).join("")}<small>你的原始数字 · 选择三个人物</small></div>`;
    return `<main class="numeric-board"><section class="numeric-foe-row"><div class="numeric-composition" aria-label="对手构成，不对应位置" title="仅知构成，不知位置">${o.opponent.tiers.map((x) => `<span class="tier-${x}" aria-label="${x}">${x}</span>`).join("")}</div><div class="numeric-slots foe-slots">${foe}</div></section><div class="numeric-center"><span>${esc(phaseName[o.phase] ?? o.phase)}</span><strong>◉ ${o.pot}</strong><small>奖池</small></div><section class="numeric-own-row"><div class="numeric-slots">${mine}</div></section></main>`;
  }

  private slotCard(
    x: { effectId: string; number: number } | null,
    i: number,
    seat: 0 | 1,
    o: NumericObservation,
  ) {
    const eq = (seat === 0 ? o.me.equipment : o.opponent.equipment)[i] ?? null;
    const pow = o.result?.powers?.[seat]?.[i],
      infoId = `slot-${seat}-${i}`,
      placement = seat === 0 && o.phase === "place" && o.toAct.includes(0);
    const card = x ? characterById(x.effectId) : null,
      c = x ? character(x.effectId) : null,
      a = x ? cardArt(x.effectId) : "";
    const detail = `${card?.text ?? "人物与精确数字在摊牌前隐藏。装备公开，构成不对应位置。"}${eq ? " 装备：" + equipmentById(eq.id, eq.tier as NumericEquipmentTier).text : ""}`;
    const isDown =
      !x ||
      (seat === 1 &&
        !!o.result?.powers &&
        this.outcomeHand !== o.handNo &&
        !reducedMotion());
    const front = x
      ? `<div class="art ${this.hooks.art.has(a) ? "has-portrait" : ""}"><span class="glyph">${c ? SIN_LATIN[c.sin] : ""}</span>${this.hooks.art.has(a) ? `<img class="portrait" src="art/${a}.webp" alt="" draggable="false">` : ""}<i class="varnish"></i>${this.equipPill(eq)}</div><i class="orn"></i><span class="sin-tag">${c ? SIN_LATIN[c.sin] : ""}</span><div class="plate"><span>${esc(card!.name)}</span></div><div class="text">${esc(card!.summary ?? card!.text)}</div><div class="stats"><span class="numeric-position">${i + 1}</span><button class="stat atk numeric-power" ${placement ? `data-nact="swap" data-arg="n,${i}" draggable="true" data-drag="n" data-pos="${i}"` : ""} aria-label="${i + 1}号位数字 ${x.number}${pow !== undefined ? "，力量 " + pow : ""}">${pow ?? x.number}</button><span class="numeric-raw">${pow !== undefined ? "原数 " + x.number : "原数"}</span></div><button class="info-btn" data-nact="info" data-arg="${infoId}" aria-label="查看${card!.name}">?</button><i class="linen"></i><i class="sheen"></i><i class="gloss"></i>`
      : "";
    return cardShell({
      classes: `card person fr-${currentFrame()} foil numeric-slot ${seat === 1 ? "foe-slot" : ""} ${isDown ? "down" : ""} ${placement ? "clickable" : ""} ${placement && this.swap?.pos === i ? "selected" : ""}`,
      attributes: `style="--sin:${c ? SIN_COLOR[c.sin] : "var(--gold)"}" data-key="numeric-${o.handNo}-${seat}-${i}" data-unit="${seat}-${i}" data-info="${infoId}" data-ntitle="${esc(card?.name ?? "暗牌")}" data-ntext="${esc(detail)}" ${placement ? `data-own-pos="${i}" data-nact="swap" data-arg="e,${i}" draggable="true" data-drag="e" data-pos="${i}" role="button" tabindex="0" aria-label="${i + 1}号位 ${card?.name}，点击或拖拽交换人物"` : ""}`,
      front,
      back: !x
        ? `${this.equipPill(eq)}<button class="info-btn" data-nact="info" data-arg="${infoId}" aria-label="查看对手${i + 1}号位公开装备">?</button>`
        : "",
    });
  }

  private equipPill(x: { id: string; tier: string } | null) {
    if (!x) return "";
    const e = equipmentById(x.id, x.tier as NumericEquipmentTier);
    return `<div class="equip numeric-equip" title="${esc(installLabel(x) + "：" + e.text)}"><span aria-hidden="true">${e.icon}</span> ${esc(e.name)}</div>`;
  }

  private draftDock(o: NumericObservation) {
    return `<section class="numeric-dock numeric-draft"><div class="numeric-dock-title"><h3>选人物 <small>${o.me.kept.length}/3</small></h3><span>${o.me.kept.map((id) => effectName(id)).join(" · ")}</span>${!o.me.rerolled ? '<button data-nact="reroll">换一批</button>' : ""}</div><div class="numeric-cards">${o.me.current.map((id, i) => this.effectCard(id, i, false)).join("")}</div><small class="numeric-hint">同名可重复选 · 候选可换一次 · 卡上 ? 查看完整规则</small></section>`;
  }

  private effectCard(id: string, index: number, selected: boolean) {
    const c = character(id),
      d = characterById(id),
      a = cardArt(id);
    return cardShell({
      classes: `card person fr-${currentFrame()} foil clickable numeric-effect-card ${selected ? "selected" : ""}`,
      attributes: `style="--sin:${SIN_COLOR[c.sin]}" data-nact="keep" data-arg="${index}" role="button" tabindex="0" aria-label="选择${d.name}" data-info="${id}" data-ntitle="${esc(d.name)}" data-ntext="${esc(d.text)}" data-key="offer-${index}-${id}"`,
      front: `<div class="art has-portrait">${this.hooks.art.has(a) ? `<img class="portrait" src="art/${a}.webp" alt="" draggable="false">` : ""}<span class="glyph">${SIN_LATIN[c.sin]}</span><i class="varnish"></i></div><i class="orn"></i><span class="sin-tag">${SIN_LATIN[c.sin]}</span><div class="plate"><span>${esc(d.name)}</span></div><div class="text">${esc(d.summary ?? d.text)}</div><button class="info-btn" data-nact="info" data-arg="${id}" aria-label="查看${d.name}">?</button><i class="linen"></i><i class="sheen"></i><i class="gloss"></i>`,
    });
  }

  private placeDock(o: NumericObservation) {
    return `<section class="numeric-dock"><h3>配对人物与数字</h3><p>拖动人物牌交换人物；拖动数字徽章交换数字。也可分别点两张牌或两个数字。锁阵后不能再改。</p>${this.swap ? `<p class="numeric-selection" role="status">已选 ${this.swap.pos + 1} 号${this.swap.kind === "e" ? "人物" : "数字"}，再点目标位置交换。</p>` : ""}<button class="primary" data-nact="place">锁定三个位置</button></section>`;
  }

  private bettingDock(o: NumericObservation) {
    const call =
      o.betting.toCall > 0
        ? `<button class="call" data-nact="call">跟注 ${Math.min(o.stacks[0], o.betting.toCall)}${o.betting.toCall >= o.stacks[0] ? "（全押）" : ""}</button>`
        : `<button data-nact="check">过牌</button>`;
    const canRaise = o.stacks[0] > o.betting.toCall;
    return `<section class="numeric-dock"><h3>下注 · 本轮已投 ${o.betting.roundBet[0]} · 对手要价 ${o.betting.target}</h3><p>过牌不花筹码。加注填“本轮加到多少”；至少加到 ${o.betting.minRaiseTo}。全押被跟注后立即开战，未定的额外效果关闭。</p><div class="numeric-bet-form">${canRaise ? `<label>${o.betting.target ? "加到" : "下注"} <input aria-label="下注金额" type="number" min="${o.betting.minRaiseTo}" max="${o.betting.roundBet[0] + o.stacks[0]}" step="1" data-ninput="amount" value="${this.amount}"></label><button data-nact="${o.betting.target ? "raise" : "bet"}">${o.betting.target ? "加到" : "下注"} <span data-amount>${this.amount}</span></button>` : ""}${call}<button class="allin" data-nact="allIn">全押 ${o.stacks[0]}</button><button class="fold" data-nact="fold">弃牌</button></div></section>`;
  }

  private equipDock(o: NumericObservation) {
    const tier =
      o.round <= 3 ? "normal" : o.round <= 5 ? "replace-1" : "replace-2";
    const offers =
      o.me.offers
        ?.map((id, i) => [id, i] as const)
        .map(([id, i]) => {
          const e = equipmentById(id, tier as NumericEquipmentTier);
          return `<div class="numeric-offer" data-info="offer-${i}" data-ntitle="${esc(e.name)}" data-ntext="${esc(e.text)}"><b><i aria-hidden="true">${e.icon}</i> ${esc(installLabel({ id, tier }))}</b><span>${esc(e.summary ?? e.text)}</span><button data-nact="info" data-arg="offer-${i}">规则详情</button><div>${[0, 1, 2].map((p) => `<button data-nact="equip" data-arg="${i},${p}" ${o.round <= 3 && o.me.equipment[p] ? "disabled" : ""}>${o.round <= 3 && o.me.equipment[p] ? "已占用 " : o.me.equipment[p] ? "替换 " : "装到 "}${p + 1}号位</button>`).join("")}</div></div>`;
        })
        .join("") ?? "";
    return `<section class="numeric-dock"><h3>选择装备与位置</h3><p>每件装备都有基础力量，关键词或条件提供额外收益。双方选完一起公开。</p><div class="numeric-offers">${offers}</div><button data-nact="operate" data-arg="0">放弃安装（不退操作费）</button></section>`;
  }

  private dock(o: NumericObservation) {
    if (o.result || o.phase === "result" || o.phase === "over")
      return this.resultDock(o);
    if (!o.toAct.includes(0))
      return `<section class="numeric-dock numeric-wait" role="status"><span class="numeric-thinking" aria-hidden="true">✦</span> 对手思考中</section>`;
    if (o.phase === "draft") return this.draftDock(o);
    if (o.phase === "place") return this.placeDock(o);
    if (o.phase === "bet") return this.bettingDock(o);
    if (o.phase === "operate")
      return `<section class="numeric-dock"><h3>第 ${o.round} 轮 · 装备机会</h3><p>${o.round <= 3 ? "普通装备只能装空位。" : `本轮为替换${o.round <= 5 ? "Ⅰ" : "Ⅱ"}，可覆盖原装备，新装备数值更低。`}付费后看三选一，放弃不退费；双方决定完一起公开。</p><button class="primary" data-nact="operate" data-arg="1" ${o.canEquip ? "" : "disabled"}>付 ${o.opFee} 筹码看装备</button><button data-nact="operate" data-arg="0">跳过（免费）</button></section>`;
    if (o.phase === "equip") return this.equipDock(o);
    const effect = o.effects[o.round - 1];
    const d = effect ? effectById(effect.id) : null;
    if (o.phase === "vote")
      return `<section class="numeric-dock"><h3>本轮表决：${esc(d?.name ?? "额外效果")}</h3><p>${esc(d?.text ?? "")}</p><p>双方选同一个答案就直接确定；意见不同时再暗标决定。</p><button class="primary" data-nact="vote" data-arg="1">启用</button><button data-nact="vote" data-arg="0">不启用</button></section>`;
    if (o.phase === "bid")
      return `<section class="numeric-dock"><h3>意见不同：暗标决定「${esc(d?.name ?? "额外效果")}」</h3><p>双方秘密出价，较高者的表决生效。双方都付出价，筹码进入奖池；同价按本手庄家（${o.dealer === 0 ? "你" : "对手"}）的表决。可以出 0，上限 ${o.bidCap}。</p><label>暗标出价 <input aria-label="暗标出价" type="number" min="0" max="${o.bidCap}" step="1" data-ninput="amount" value="${this.amount}"></label><button data-nact="bid">出价</button></section>`;
    return `<section class="numeric-dock"><p>等待双方锁定……</p></section>`;
  }

  private resultDock(o: NumericObservation) {
    const r = o.result;
    const stages = {
      environment: "场地",
      control: "沉默与封印",
      character: "人物",
      equipment: "装备",
      keyword: "关键词",
    };
    const lines =
      r?.trace
        ?.map(
          (x) =>
            `<li>${esc(typeof x === "string" ? x : `${stages[x.stage]} · ${x.targetSeat === 0 ? "你" : "对手"}${x.targetPos + 1}号位：${x.text}（${x.before} → ${x.after}）`)}</li>`,
        )
        .join("") ?? "";
    const winner =
      r?.winner === 0 ? "你赢了" : r?.winner === 1 ? "对手获胜" : "平局";
    const comparisons = r?.powers
      ? `<p>${[0, 1, 2].map((i) => `${i + 1}号位：你 ${r.powers![0][i]} / 对手 ${r.powers![1][i]}（${r.lineWinners?.[i] === null ? "平" : r.lineWinners?.[i] === 0 ? "你胜" : "对手胜"}）`).join("；")}</p>`
      : "";
    return `<section class="numeric-dock numeric-result"><h2>${winner}</h2><p>本手奖池 ${r?.pot ?? 0} 已分配：你 +${r?.payouts?.[0] ?? 0}，对手 +${r?.payouts?.[1] ?? 0}。</p>${comparisons}<p>${esc(r?.lines?.filter((line) => !r.powers || !/^[123]号位：/.test(line)).join("；") ?? "")}</p><details><summary>查看逐步计算</summary><ol>${lines}</ol></details>${r?.powers ? `<button data-nact="replay">重看对位比较</button>` : ""}${o.phase !== "over" ? `<button class="primary" data-nact="next">下一手</button>` : `<p>一方筹码已归零，本桌结束。</p><button data-nact="exit">回到开始界面</button>`}</section>`;
  }

  /** 结算回放：先逐条高亮三条固定对位线，再留下完整公式日志。 */
  private async playComparison(o: NumericObservation) {
    if (!o.result?.powers) return;
    this.replaying = true;
    const token = this.replayToken;
    for (let i = 0; i < 3; i++) {
      if (token !== this.replayToken || !this.table) return;
      const cards = [
        this.root.querySelector<HTMLElement>(`[data-unit="0-${i}"]`),
        this.root.querySelector<HTMLElement>(`[data-unit="1-${i}"]`),
      ];
      for (const card of cards) {
        card?.classList.remove("down");
        card?.classList.add("numeric-clash");
      }
      const duration = reducedMotion() ? 0 : 560,
        start = performance.now();
      await new Promise<void>((resolve) => {
        const tick = () => {
          if (token !== this.replayToken) {
            resolve();
            return;
          }
          const t = duration
            ? Math.min(1, (performance.now() - start) / duration)
            : 1;
          cards.forEach((card, seat) => {
            const n = card?.querySelector(".numeric-power");
            if (n)
              n.textContent = String(
                Math.round(
                  o.result!.teams![seat][i].number +
                    (o.result!.powers![seat][i] -
                      o.result!.teams![seat][i].number) *
                      t,
                ),
              );
          });
          if (t < 1) requestAnimationFrame(tick);
          else resolve();
        };
        requestAnimationFrame(tick);
      });
      cards.forEach((card, seat) => {
        card?.classList.remove("numeric-clash");
        card?.classList.add(
          o.result!.lineWinners?.[i] === seat ? "numeric-win" : "numeric-loss",
        );
      });
    }
    if (token !== this.replayToken) return;
    this.outcomeHand = o.handNo;
    this.replaying = false;
    this.draw();
  }

  private tutorialView() {
    const [title, body] = this.tutorial[this.tutorialPage];
    return `<div class="numeric-tutorial"><div class="numeric-tutorial-panel" role="dialog" aria-modal="true" aria-label="新手教程"><small>新手教程 ${this.tutorialPage + 1}/${this.tutorial.length}</small><h2>${esc(title)}</h2><p>${esc(body)}</p><details><summary>按需查阅：术语与结算顺序</summary><p>“原始数字”是发牌时的数字；“力量”是算完加减后的结果。“对位”是对方相同编号的位置；左右邻位是你自己的相邻队友。沉默只关掉人物效果，封印只关掉装备效果。并列最高或最低也算满足条件。</p><p>${esc(NUMERIC_SETTLEMENT_TEXT)}</p>${Object.values(
      KEYWORDS,
    )
      .map((k) => `<p><b>${k.icon} ${k.name}</b>：${esc(k.description)}</p>`)
      .join(
        "",
      )}<p>每轮最多看一次装备。第4、5轮为替换Ⅰ，第6、7轮为更弱的替换Ⅱ；已装的装备不会随轮数自动变弱。暗标每人最多20枚，也不能超过手中筹码；双方出价都进奖池，同价听本手庄家。教程中的筹码均为游戏内筹码。</p></details><div class="numeric-tutorial-actions"><button data-nact="tutorialSkip">先玩，稍后再看</button>${this.tutorialPage ? `<button data-nact="tutorialPrev">上一步</button>` : ""}<button class="primary" data-nact="tutorialNext">${this.tutorialPage + 1 === this.tutorial.length ? "开始对战" : "下一步"}</button></div></div></div>`;
  }
}
