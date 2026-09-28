import { battle } from "./battle.js";
import { hypotheses } from "./agent.js";
import { card, gear, FIELDS, INTENT_RULESET } from "./content.js";
import {
  OFF,
  type Observation,
  type Unit,
  type Trace,
  type Battle,
  type Plan,
} from "./types.js";

export const BASIC_TEXT = {
  shield:
    "护幕：自身首次实际需要抵挡的敌方削弱，最多挡1。主动技能关闭时仍有效。",
  reserve:
    "蓄能：主阶段收到的强化累计暂存至多2，收尾返还，并额外获得暂存量的一半（向下取整）。主动技能关闭时仍有效。",
  relay: "接力：首次收到队友强化后，自身再获得1。主动技能关闭时仍有效。",
};
const MODES: Record<string, [string, string]> = {
  EN2: ["守面", "攻面"],
  SL2: ["守面", "攻面"],
  LU2: ["分流增益", "分流削弱"],
  PR3: ["先朝贡后册封", "先册封后朝贡"],
  WR4: ["集中索债", "逐一追责"],
  GR4: ["收租", "再贷"],
  GL5: ["消化", "反刍"],
  EN4: ["取代", "歪曲"],
  SL4: ["先还债", "先享受"],
  LU4: ["独占", "移情"],
  LU5: ["优先补偿", "平分并自强"],
};
export const modeName = (id: string, mode: 0 | 1) =>
  MODES[id]?.[mode] ?? "发动";
export function planText(id: string, plan: Plan, opponent = false) {
  return !plan.on
    ? "技能关闭"
    : `${modeName(id, plan.mode)}${plan.targets.length ? " → " + plan.targets.map((t) => `${(t.side === "ally") !== opponent ? "己" : "敌"}${t.pos + 1}位`).join(" / ") : " · 无指定目标"}`;
}
const GEAR_IO: Record<string, string> = {
  G01: "首笔技能强化+2，自付1",
  G02: "首次主阶段收强化，分半给低原数队友",
  G03: "主阶段队友收强化时分1到这里，共至多4",
  G04: "每笔敌方削弱减半",
  G05: "首笔敌方削弱最多挡3",
  G06: "首笔主阶段削弱分半给高原数队友",
  G07: "技能实际削敌的一半回补自己，累计最多3",
  G08: "主阶段技能每笔强化后补低原数队友1，最多3次",
  G09: "主阶段收强化暂存至多4，收尾返还并加半",
  G10: "首次实际受敌方削弱，反还来源2",
  G11: "主阶段收强化分半给另两位，累计最多分6",
  G12: "首笔技能强化+3，后续−1",
  G13: "主阶段每笔收强化转1给左邻，累计最多3",
  G14: "首笔敌方削弱至多2转为自强",
  G15: "主阶段技能强化延到收尾，前两笔各+1",
  G16: "技能的己方代价每次少1，共最多少2",
  G17: "前两笔主阶段技能强化各+2，每次自付1",
  G18: "低原数队友首笔主阶段削弱转来并减1",
  G19: "首笔主阶段削弱分半给低原数队友",
  G20: "首笔主阶段削弱延至收尾偿还",
  G21: "回收己方格挡、弃增益和技能代价，收尾至多+2",
  G22: "主阶段每笔强化转1给高原数队友，最多3次",
  G23: "技能强化低原数队友+1，其他强化−1",
  G24: "主阶段高于均值则强化转最低队友；否则前两笔+1",
};
export function publicAnalysis(o: Observation, p: number): string {
  const g = o.foe.equipment[p];
  return g
    ? `条件：${GEAR_IO[g]}；暗技未知。`
    : "暗牌：技能内容与基础能力未知，输出待揭示。";
}
export function labelName(label: string): string {
  const base = label.match(/^(?:G\d+|F\d+|[A-Z]{2}\d+)/)?.[0];
  if (base) {
    try {
      return (
        (base.startsWith("G") && /^G\d/.test(base)
          ? gear(base).name
          : base.startsWith("F")
            ? FIELDS.find((f) => f.id === base)?.name
            : card(base).name) || label
      );
    } catch {
      /* descriptive internal label */
    }
  }
  return (
    (
      { shield: "护幕", reserve: "蓄能", relay: "接力" } as Record<
        string,
        string
      >
    )[label] ?? label
  );
}
export const readableModifier = (s: string) =>
  s.replace(/\b(?:G\d+|F\d+|[A-Z]{2}\d+|shield|reserve|relay)\b/g, labelName);
export function traceText(e: Trace): string {
  return `${e.phase === "tail" ? "收尾" : "主阶段"} · ${e.seat === 0 ? "己" : "敌"}${e.source + 1}位「${labelName(e.label)}」→ ${e.targetSeat === 0 ? "己" : "敌"}${e.target + 1}位：输入${e.proposed}点${{ gain: "强化", loss: "削弱", cost: "代价" }[e.kind]}${e.modifiers.length ? "；" + e.modifiers.map(readableModifier).join("；") : ""}；实际${e.kind === "gain" ? "增加" : "减少"}${e.applied}，力量${e.before} → ${e.after}`;
}
export interface UnitAnalysis {
  pos: number;
  name: string;
  skill: string;
  basic: string;
  equipment: string;
  field: string;
  intent: string;
  changes: string[];
  steps: string[];
  inputs: string[];
  outputs: string[];
  final: number;
  sampleMin: number;
  sampleMax: number;
  comparisons: { label: string; delta: number[] }[];
}
/** Compact player text; the full trace remains internal. No hidden-card certainty is implied. */
export function compactAnalysis(a: Analysis, p: number): string {
  const events = a.battle.trace,
    incoming = events.filter((e) => e.targetSeat === 0 && e.target === p);
  const sum = (list: Trace[], kind: Trace["kind"]) =>
    list.filter((e) => e.kind === kind).reduce((n, e) => n + e.applied, 0);
  const out = events.filter((e) => e.seat === 0 && e.source === p);
  const short = (n: number) =>
    Math.abs(n) < 1000 ? String(n) : `${(n / 1000).toPrecision(2)}千`;
  const vector = (ns: number[]) =>
    ns
      .map((n, p) => (n ? `${p + 1}位${n > 0 ? "+" : ""}${short(n)}` : ""))
      .filter(Boolean)
      .join("/") || "无净变化";
  const u = a.units[p];
  const prefix = a.kind === "actual" ? "实" : "例";
  const inputs = [
    ["收", sum(incoming, "gain")],
    ["受削", sum(incoming, "loss")],
    ["付", sum(incoming, "cost")],
  ] as const;
  const outputs = [
    [
      "送友",
      sum(
        out.filter((e) => e.targetSeat === 0),
        "gain",
      ),
    ],
    [
      "削敌",
      sum(
        out.filter((e) => e.targetSeat === 1),
        "loss",
      ),
    ],
  ] as const;
  const io = `${prefix}：${
    inputs
      .filter(([, n]) => n)
      .map(([label, n]) => label + short(n))
      .join("、") || "无输入"
  }→${
    outputs
      .filter(([, n]) => n)
      .map(([label, n]) => label + short(n))
      .join("、") || "无输出"
  }`;
  const impact = `装${vector(u.comparisons[1].delta)}；场${vector(u.comparisons[2].delta)}`;
  const full = `${io}；${impact}`;
  if ([...full].length <= 50) return full;
  // Dense outcomes retain all three positional deltas in a compact layout; no intermediate trace.
  const dense = (ns: number[]) =>
    ns.map((n) => `${n > 0 ? "+" : ""}${short(n)}`).join("/");
  const compact = `${prefix}：收${short(sum(incoming, "gain"))}削${short(sum(incoming, "loss"))}付${short(sum(incoming, "cost"))}；友${short(
    sum(
      out.filter((e) => e.targetSeat === 0),
      "gain",
    ),
  )}敌${short(
    sum(
      out.filter((e) => e.targetSeat === 1),
      "loss",
    ),
  )}；装${dense(u.comparisons[1].delta)}；场${dense(u.comparisons[2].delta)}`;
  return [...compact].length <= 50 ? compact : `${io}；终${short(u.final)}`;
}
export interface Analysis {
  ruleset: string;
  kind: "actual" | "scenario";
  assumption: string;
  scenarios: number;
  example: Unit[];
  battle: Battle;
  units: UnitAnalysis[];
}
/** Only legal observations enter this interpreter. Samples are illustrations, never bounds or win probabilities. */
export function analyse(o: Observation, edited?: Unit[]): Analysis | null {
  if (!o.me.units) return null;
  const actual = !!o.result?.battle && !!o.result.teams;
  const own = structuredClone(
    actual ? o.result!.teams![o.seat] : (edited ?? o.me.units),
  );
  const fields = o.effects.filter((f) => f.active && f.id).map((f) => f.id!);
  const opponents = actual
    ? [o.result!.teams![1 - o.seat]]
    : hypotheses(o, 6, true, true, 419);
  const options = { initiative: (o.initiative === o.seat ? 0 : 1) as 0 | 1 };
  const resolved = opponents.map((foe) => battle([own, foe], fields, options)),
    example = resolved[0];
  const field = fields
    .map((id) => {
      const f = FIELDS.find((x) => x.id === id)!;
      return `${f.name}：${f.text}`;
    })
    .join("；");
  const compare = (team: Unit[], fs = fields) =>
    battle([team, opponents[0]], fs, {
      ...options,
      trace: false,
    }).powers[0].map((n, p) => example.powers[0][p] - n);
  return {
    ruleset: INTENT_RULESET,
    kind: actual ? "actual" : "scenario",
    assumption: actual
      ? "实际摊牌复盘：所有身份和模式已揭示，以下为真实结算。"
      : "条件演算：从公开构成、装备和已确认指向生成6个合法敌方示例；逐步明细采用示例1。样本跨度不是保证范围，不是胜率，也不代表真实暗牌。未提交的己方技能仅用于本地预览。",
    scenarios: opponents.length,
    example: opponents[0],
    battle: example,
    units: own.map((u, p) => {
      const c = card(u.id),
        related = example.trace.filter(
          (e) =>
            (e.seat === 0 && e.source === p) ||
            (e.targetSeat === 0 && e.target === p),
        );
      const noSkill = structuredClone(own);
      noSkill[p].plan = OFF();
      const noGear = structuredClone(own);
      noGear[p].gear = null;
      const changes = [
        ...new Set(related.flatMap((e) => e.modifiers.map(readableModifier))),
      ];
      return {
        pos: p,
        name: c.name,
        skill: c.text,
        basic: c.basic ? BASIC_TEXT[c.basic] : "无基础能力。",
        equipment: u.gear
          ? `${gear(u.gear).name}：${gear(u.gear).text}`
          : "未安装装备。",
        field,
        intent: planText(u.id, u.plan),
        changes,
        steps: related.map(traceText),
        inputs: related
          .filter((e) => e.targetSeat === 0 && e.target === p)
          .map(traceText),
        outputs: related
          .filter((e) => e.seat === 0 && e.source === p)
          .map(traceText),
        final: example.powers[0][p],
        sampleMin: Math.min(...resolved.map((b) => b.powers[0][p])),
        sampleMax: Math.max(...resolved.map((b) => b.powers[0][p])),
        comparisons: [
          { label: "此技能发动，相比关闭", delta: compare(noSkill) },
          { label: "此装备安装，相比移除", delta: compare(noGear) },
          { label: "当前场地，相比无场地", delta: compare(own, []) },
        ],
      };
    }),
  };
}
