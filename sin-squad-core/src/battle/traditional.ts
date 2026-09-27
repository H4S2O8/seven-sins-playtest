import type { Seat } from "../types.js";

export interface TraditionalSlot { effectId: string; number: number; equipmentId?: string | null; target?: number }
export interface TraditionalInput { teams: [TraditionalSlot[], TraditionalSlot[]]; arenaText?: string }
export interface TraditionalResult {
  winner: Seat | null;
  reason: "达成规则";
  rounds: number;
  events: Array<{ round: number; type: "note"; text: string }>;
  final: [any[], any[]]; start: [any[], any[]]; timeline: any[]; frames: any[];
  interest: [number, number];
}

export function traditionalPower(s: TraditionalSlot, foe: TraditionalSlot, pos: number, team: TraditionalSlot[], foeTeam: TraditionalSlot[]): number {
  let n = s.number;
  const id = s.effectId;
  if (["WR1", "WR3", "WR4"].includes(id)) n += 1;
  if (["WR2"].includes(id) && s.number < foe.number) n += 2;
  if (["GR1", "GR3", "GR4"].includes(id) && team.reduce((a, x) => a + x.number, 0) >= 18) n += 2;
  if (["GR2"].includes(id) && s.number === Math.min(...team.map((x) => x.number))) n += 2;
  if (["GL1"].includes(id) && foe.number <= 4) n += 3;
  if (["GL3", "GL5"].includes(id) && foe.number <= 5) n += 2;
  if (["EN2"].includes(id)) n = Math.max(n, foe.number);
  if (["EN3", "EN4"].includes(id) && foe.equipmentId) n += 2;
  if (["SL1", "SL4"].includes(id) && s.number <= 4) n += 3;
  if (["SL2"].includes(id) && s.number !== Math.max(...team.map((x) => x.number))) n += 2;
  if (["SL3"].includes(id) && team.reduce((a, x) => a + x.number, 0) <= 15) n += 3;
  if (["PR1"].includes(id) && s.number >= 8) n += 2;
  if (["PR2"].includes(id) && Math.abs(s.number - foe.number) >= 3) n += 2;
  if (["PR3"].includes(id) && foe.number === Math.max(...foeTeam.map((x) => x.number))) n += 3;
  if (["LU1", "LU5"].includes(id) && pos === 1) n += 2;
  if (["LU2"].includes(id) && s.number === foe.number) n += 3;
  if (["LU3", "LU4"].includes(id) && foe.number > s.number) n += 2;
  if (s.equipmentId) {
    const e: Record<string, number> = { E01: 3, E03: 1, E04: 2, E05: 1, E06: 2, E07: pos === 0 || pos === 2 ? 1 : 0, E08: 1, E09: foe.number <= 5 ? 1 : 0, E10: 1, E11: team.reduce((a, x) => a + x.number, 0) >= 20 ? 1 : 0, E12: 1, E02: s.number < 5 ? 3 : 0 };
    n += e[s.equipmentId] ?? 0;
  }
  return n;
}

/** 传统牌桌的 2047 式单值碰撞：每个位置同时比较最终力量，输的一方该位置出局。 */
export function runTraditionalBattle(input: TraditionalInput): TraditionalResult {
  let a = 0, b = 0;
  const notes: Array<{ round: number; type: "note"; text: string }> = [];
  for (let i = 0; i < 3; i++) {
    const x = input.teams[0][i], y = input.teams[1][i];
    const targetX = x.target ?? i, targetY = y.target ?? i;
    const tx = input.teams[1][targetX] ?? y, ty = input.teams[0][targetY] ?? x;
    const sx = traditionalPower(x, tx, i, input.teams[0], input.teams[1]), sy = traditionalPower(y, ty, i, input.teams[1], input.teams[0]);
    if (sx > sy) { a++; notes.push({ round: 1, type: "note", text: `${i + 1}号位：${sx} 对 ${sy}，我方胜` }); }
    else if (sy > sx) { b++; notes.push({ round: 1, type: "note", text: `${i + 1}号位：${sy} 对 ${sx}，对手胜` }); }
    else notes.push({ round: 1, type: "note", text: `${i + 1}号位：${sx} 对 ${sy}，平` });
  }
  const winner: Seat | null = a === b ? null : a > b ? 0 : 1;
  return { winner, reason: "达成规则", rounds: 1, events: notes, final: [[], []], start: [[], []], timeline: [], frames: [], interest: [0, 0] };
}
