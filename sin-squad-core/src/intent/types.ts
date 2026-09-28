export type Seat = 0 | 1;
export type Grade = "S" | "C1" | "C2" | "C3";
export type Mark = "aim" | "reinforce" | "choice" | "flip";
export type Target = { side: "ally" | "enemy"; pos: number };
export type Plan = { on: boolean; targets: Target[]; mode: 0 | 1 };
export type Signal = { on: boolean; kind: Mark | "off"; targets: Target[] };
export interface Unit {
  id: string;
  raw: number;
  gear: string | null;
  plan: Plan;
}
export interface Card {
  id: string;
  name: string;
  grade: Grade;
  mark: Mark;
  targets: ("ally" | "other" | "enemy")[];
  modes: boolean;
  basic?: "shield" | "reserve" | "relay";
  text: string;
  uses: [string, string];
  mastery?: string;
}
export interface Gear {
  id: string;
  name: string;
  text: string;
  uses: [string, string];
}
export interface Arena {
  id: string;
  name: string;
  text: string;
  uses: [string, string];
}
export interface Event {
  seat: Seat;
  source: number;
  targetSeat: Seat;
  target: number;
  amount: number;
  kind: "gain" | "loss" | "cost";
  depth: number;
  label: string;
}
export interface Trace extends Event {
  proposed: number;
  applied: number;
  before: number;
  after: number;
  modifiers: string[];
  phase?: "main" | "tail";
  origin?: "skill" | "gear" | "basic" | "field";
}
export interface Battle {
  powers: [number[], number[]];
  winner: Seat | null;
  lanes: (Seat | null)[];
  trace: Trace[];
  interactions: string[];
}
export type Action =
  | { type: "draft"; indices: number[] }
  | { type: "redraw" }
  | { type: "place"; units: number[]; numbers: number[] }
  | { type: "plan"; plans: Plan[] }
  | { type: "operate"; buy: boolean }
  | { type: "equip"; offer: number; pos: number }
  | { type: "bid"; amount: number; yes: boolean }
  | { type: "check" }
  | { type: "call" }
  | { type: "fold" }
  | { type: "raise"; to: number };
export interface Observation {
  seat: Seat;
  initiative: Seat;
  seedLabel: number;
  phase: string;
  round: number;
  actor: Seat[];
  effects: { id: string | null; active: boolean | null }[];
  me: {
    numbers: number[];
    offer: string[];
    kept: string[];
    units: Unit[] | null;
    gearOffers: string[];
    redrawn: boolean;
  };
  foe: { tiers: number[]; equipment: (string | null)[]; signals: Signal[] };
  pot: number;
  stacks: [number, number];
  bet: { call: number; min: number; paid: [number, number]; target: number };
  history: { seat: Seat; round: number; type: string; amount?: number }[];
  result: {
    winner: Seat | null;
    fold: boolean;
    battle: Battle | null;
    payouts: [number, number];
    teams?: [Unit[], Unit[]];
  } | null;
}
export const OFF = (): Plan => ({ on: false, targets: [], mode: 0 });
