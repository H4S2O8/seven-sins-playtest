import { battle } from "./battle.js";
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
export function publicAnalysis(o: Observation, p: number): string {
  const g = o.foe.equipment[p];
  return g
    ? `装备「${gear(g).name}」：${gear(g).text}对方技能尚未揭示，不能确定最终输出。`
    : "对方人物尚未揭示，暂时无法确定技能与基础能力的效果。";
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
/** Player-facing endpoints in natural language; the event chain stays internal. */
export function compactAnalysis(a: Analysis, p: number): string {
  const events = a.battle.trace,
    incoming = events.filter((e) => e.targetSeat === 0 && e.target === p);
  const sum = (list: Trace[], kind: Trace["kind"]) =>
    list.filter((e) => e.kind === kind).reduce((n, e) => n + e.applied, 0);
  const out = events.filter((e) => e.seat === 0 && e.source === p);
  const u = a.units[p];
  const positions = ["左位", "中位", "右位"];
  const facts: string[] = [];
  const received = sum(incoming, "gain"),
    lost = sum(incoming, "loss"),
    paid = sum(incoming, "cost");
  if (received) facts.push(`收到${received}点强化`);
  if (lost) facts.push(`受到${lost}点削弱`);
  if (paid) facts.push(`支付${paid}点力量`);
  for (let q = 0; q < 3; q++) {
    const friendly = out.filter((e) => e.targetSeat === 0 && e.target === q);
    const delivered = sum(friendly, "gain"),
      cost = sum(friendly, "cost");
    const attacked = sum(
      out.filter((e) => e.targetSeat === 1 && e.target === q),
      "loss",
    );
    // Self-strengthening is already included in the received amount, not counted twice in prose.
    if (q !== p && delivered)
      facts.push(`向${positions[q]}送出${delivered}点强化`);
    if (q !== p && cost) facts.push(`让${positions[q]}队友支付${cost}点力量`);
    if (attacked) facts.push(`削弱敌方${positions[q]}${attacked}点力量`);
  }
  if (!facts.length) facts.push("没有产生力量变化");
  facts.push(`最终力量为${u.final}`);
  const impact = (description: string, delta: number[]) => {
    if (!description.includes("：")) return "";
    const name = description.split("：")[0];
    const changes = delta.flatMap((n, q) =>
      n ? [`${positions[q]}${n > 0 ? "多" : "少"}${Math.abs(n)}点`] : [],
    );
    return changes.length
      ? `${name}使${changes.join("、")}力量。`
      : `${name}没有改变本方最终力量。`;
  };
  return `${a.kind === "actual" ? "本次" : "本例"}${facts.join("，")}。${impact(u.equipment, u.comparisons[1].delta)}${impact(u.field, u.comparisons[2].delta)}`;
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
/** Preview-only stand-ins: WR3 has no basic ability and its active skill stays off. */
export function previewOpponents(o: Observation): Unit[] {
  return [0, 1, 2].map((p) => ({
    id: "WR3",
    raw: 6,
    gear: o.foe.equipment[p] ?? null,
    plan: OFF(),
  }));
}
/** Only legal observations enter this interpreter. The fixed preview is not a prediction. */
export function analyse(o: Observation, edited?: Unit[]): Analysis | null {
  if (!o.me.units) return null;
  const actual = !!o.result?.battle && !!o.result.teams;
  const own = structuredClone(
    actual ? o.result!.teams![o.seat] : (edited ?? o.me.units),
  );
  const fields = o.effects.filter((f) => f.active && f.id).map((f) => f.id!);
  const opponents = actual
    ? [o.result!.teams![1 - o.seat]]
    : [previewOpponents(o)];
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
      : "白板演算：保留敌方三个位置已公开的装备，人物没有主动技能和基础能力，隐藏数字统一按每位6点计算。6点只是固定基准，不代表对方真实数字或构成；公开指向不用于猜测技能。依赖敌方发动技能的配合可能不会触发。这不是胜率或保证结果；摊牌后改用实际敌阵。",
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
