import { FIELDS, FIELD_FITS, GEARS } from "./content.js";
import type { Observation, Unit } from "./types.js";

const READS: Record<string, [string, string]> = {
  G01: ["这个位置可能是强化的发出者", "也可能只放大一次吸取或收尾恢复"],
  G02: ["这里可能先接大笔强化，再养低数队友", "低数接收者不一定是最终争胜位"],
  G03: [
    "这里可能汇聚其他位置的多笔增益",
    "可能是牺牲接收者，随后把力量再送出去",
  ],
  G04: ["这里能更便宜地承受敌方削弱", "可能保护主力，也可能替队友接伤"],
  G05: ["这里不怕第一笔较重削弱", "先用小笔消耗护幕会改变判断"],
  G06: [
    "这里的压力可能流向另一高原数位",
    "高原数位可能有防护，也可能被当作牺牲位",
  ],
  G07: ["这里可能发出削弱并用实际命中回血", "被格挡的部分不产生恢复"],
  G08: ["这里可能发出多笔强化，顺带养低数位", "首要受益者与回声受益者可能不同"],
  G09: [
    "这里可能接自身、队友或装备转来的强化",
    "主阶段截流可能扑空；收尾实际到账仍可能触发扩散或护场",
  ],
  G10: ["攻击这里会牵连攻击来源", "它也可能等待护送过来的攻击"],
  G11: ["一条强化入口可能拆成两条支援线", "一笔变多笔也可能触发更多截流"],
  G12: [
    "首笔强化可能很大，之后输出缩水",
    "首笔目标公开，但可能经过其他节点改道",
  ],
  G13: ["这里是向左绕行的接线点", "箭头指向这里不代表最后力量留在这里"],
  G14: ["这里可能欢迎第一笔敌方削弱", "也可能主动替另一位置接伤"],
  G15: ["这个位置的技能强化可能留到收尾", "主阶段复制或截流可能没有输入"],
  G16: ["这里可能承担或分派友方代价", "降成本能保住供体，而非直接强化佩戴者"],
  G17: ["这里可能放出前两笔较大强化", "额外代价也可能让这里成为故意落后位"],
  G18: ["低原数队友可能受到这里保护", "佩戴者可能是防护核心，也可能是牺牲位"],
  G19: ["佩戴者的受压会分到低原数队友", "低数队友可能借实际受损反击"],
  G20: [
    "这里延后偿还第一笔削弱",
    "延期不免伤，对手可据此判断主阶段受损账本可能落空",
  ],
  G21: ["队伍可能用防护或支付技能代价供能", "不能仅凭这个装备锁定具体角色"],
  G22: [
    "这里的强化会流向另一高原数位",
    "原数高不代表最终强，可能只是转运目的地",
  ],
  G23: [
    "大原数佩戴者支援较小数字更划算",
    "也可能被迫装在不合适的位置，不能排除反例",
  ],
  G24: [
    "这里收到力量后可能继续转给最低力量位",
    "当前最高低会被前序技能改变，不由原数固定",
  ],
};
export function publicReads(o: Observation): string[] {
  const out = o.foe.equipment.flatMap((g, p) =>
    g
      ? [
          `敌${p + 1}位·${GEARS.find((x) => x.id === g)!.name}：${READS[g].join("；")}。`,
        ]
      : [],
  );
  o.foe.signals.forEach((s, p) => {
    if (s.on)
      out.push(
        `敌${p + 1}位公开${s.kind}，${s.targets.map((t) => `${t.side === "ally" ? "其友" : "我"}${t.pos + 1}位`).join("、") || "无目标"}：表示作用关系，不保证是增益或攻击；隐藏模式仍有分歧。`,
      );
  });
  for (const e of o.effects)
    if (e.active && e.id) {
      const fit = FIELD_FITS[e.id];
      out.push(
        `${FIELDS.find((f) => f.id === e.id)!.text} 倾向：${fit.numbers}；${fit.roles}。留意：${fit.watch}。`,
      );
    }
  return out;
}
/** Soft public-evidence likelihood, never an exclusion: paid offers can force a poor fit. */
export function equipmentFit(team: Unit[]): number {
  let weight = 1;
  team.forEach((u, p) => {
    const incoming = team.filter(
      (v) =>
        v.plan.on &&
        v.plan.targets.some((t) => t.side === "ally" && t.pos === p),
    ).length;
    if (["G03", "G09", "G11", "G13", "G22", "G24"].includes(u.gear || ""))
      weight *= 1 + Math.min(2, incoming) * 0.35;
    if (u.gear === "G23" && u.plan.on) {
      const allies = u.plan.targets.filter((t) => t.side === "ally");
      weight *= allies.length
        ? 1 + allies.filter((t) => team[t.pos].raw < u.raw).length * 0.65
        : 0.8;
    }
    if (u.gear === "G18")
      weight *=
        1 +
        (u.raw > Math.min(...team.filter((_, q) => q !== p).map((v) => v.raw))
          ? 0.35
          : 0);
    if (u.gear === "G02" || u.gear === "G22")
      weight *= 1 + (incoming ? 0.2 : 0);
  });
  return weight;
}
