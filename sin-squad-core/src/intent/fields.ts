import { FIELDS } from "./content.js";
import type { Seat } from "./types.js";

export interface FieldBonus {
  seat: Seat;
  source: number;
  target: number;
  amount: number;
  label: string;
}
/** Per-battle process hooks. They never inspect hidden identity, raw tiers or final winners. */
export class ProcessFields {
  private readonly enabled: Set<string>;
  private heat = [
    [0, 0, 0],
    [0, 0, 0],
  ];
  private furnace = [
    [0, 0, 0],
    [0, 0, 0],
  ];
  constructor(ids: string[]) {
    if (ids.some((id) => !FIELDS.some((f) => f.id === id)))
      throw Error("Unknown process field");
    this.enabled = new Set(ids);
  }
  has(id: string) {
    return this.enabled.has(id);
  }
  transfer(n: number) {
    return n * (this.has("F1") ? 2 : 1);
  }
  spill(n: number) {
    return this.has("F5") ? Math.max(0, n - 1) : 0;
  }
  paid(seat: Seat, source: number, n: number) {
    if (this.has("F4")) this.furnace[seat][source] += n;
  }
  boost(seat: Seat, source: number) {
    const n = this.furnace[seat][source];
    this.furnace[seat][source] = 0;
    return n;
  }
  guard(seat: Seat, pos: number, n: number) {
    const used = Math.min(n, this.heat[seat][pos]);
    this.heat[seat][pos] -= used;
    return used;
  }
  arrived(
    seat: Seat,
    pos: number,
    sourceSeat: Seat,
    source: number,
    n: number,
  ): FieldBonus[] {
    if (seat !== sourceSeat) return [];
    if (this.has("F6")) this.heat[seat][pos] += n;
    if (this.has("F2") && source !== pos)
      return [
        { seat, source: pos, target: (pos + 1) % 3, amount: n, label: "F2" },
      ];
    return [];
  }
  blocked(seat: Seat, pos: number, n: number): FieldBonus[] {
    return this.has("F3")
      ? [{ seat, source: pos, target: (pos + 2) % 3, amount: n, label: "F3" }]
      : [];
  }
}
