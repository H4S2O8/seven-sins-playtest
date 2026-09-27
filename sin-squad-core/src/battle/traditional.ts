import type { Seat } from "../types.js";

export interface TraditionalSlot { effectId: string; number: number; equipmentId?: string | null }
export interface TraditionalInput { teams: [TraditionalSlot[], TraditionalSlot[]]; arenaText?: string }
export interface TraditionalResult {
  winner: Seat | null;
  reason: "达成规则";
  rounds: number;
  events: Array<{ round: number; type: "note"; text: string }>;
  final: [any[], any[]]; start: [any[], any[]]; timeline: any[]; frames: any[];
  interest: [number, number];
}

/** 传统牌桌的 2047 式单值碰撞：每个位置同时比较最终力量，输的一方该位置出局。 */
export function runTraditionalBattle(input: TraditionalInput): TraditionalResult {
  const score = (s: TraditionalSlot, foe: TraditionalSlot, pos: number, team: TraditionalSlot[]) => {
    let n = s.number;
    const id = s.effectId;
    if (["WR1", "WR3", "WR4"].includes(id)) n += 1;
    if (["GR1", "GR3", "GR4"].includes(id)) n += team.reduce((a, x) => a + x.number, 0) >= 18 ? 2 : 0;
    if (["GL3", "GL5"].includes(id)) n += foe.number <= 4 ? 2 : 0;
    if (["EN2", "EN4"].includes(id)) n += Math.max(0, foe.number - n);
    if (["SL1", "SL2", "SL4"].includes(id)) n += pos === 1 ? 1 : 0;
    if (["PR1", "PR2", "PR3"].includes(id)) n += n >= 8 ? 1 : 0;
    if (["LU1", "LU2", "LU3", "LU4", "LU5"].includes(id)) n += pos === 1 ? 2 : 0;
    return n;
  };
  let a = 0, b = 0;
  const notes: Array<{ round: number; type: "note"; text: string }> = [];
  for (let i = 0; i < 3; i++) {
    const x = input.teams[0][i], y = input.teams[1][i];
    const sx = score(x, y, i, input.teams[0]), sy = score(y, x, i, input.teams[1]);
    if (sx > sy) { a++; notes.push({ round: 1, type: "note", text: `${i + 1}号位：${sx} 对 ${sy}，我方胜` }); }
    else if (sy > sx) { b++; notes.push({ round: 1, type: "note", text: `${i + 1}号位：${sy} 对 ${sx}，对手胜` }); }
    else notes.push({ round: 1, type: "note", text: `${i + 1}号位：${sx} 对 ${sy}，平` });
  }
  const winner: Seat | null = a === b ? null : a > b ? 0 : 1;
  return { winner, reason: "达成规则", rounds: 1, events: notes, final: [[], []], start: [[], []], timeline: [], frames: [], interest: [0, 0] };
}
