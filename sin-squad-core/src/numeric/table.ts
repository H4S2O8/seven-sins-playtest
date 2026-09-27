import { Rng } from "../rng.js";
import { NUMERIC_CHARACTER_IDS, NUMERIC_ARENAS, NUMERIC_RULES, NUMERIC_EFFECTS, NUMERIC_EQUIPMENT, runNumericResolution, type NumericSlot, type NumericTeam } from "./content.js";
import type { NumericAction, NumericObservation } from "./types.js";

type Seat = 0 | 1;
type Equipment = NonNullable<NumericSlot["equipment"]>;
const seats: Seat[] = [0, 1];
const other = (s: Seat): Seat => s === 0 ? 1 : 0;
const pair = (): [number, number] => [0, 0];
interface Player {
  numbers: number[]; current: string[]; seen: string[]; kept: string[]; rerolled: boolean;
  slots: NumericSlot[] | null; equipment: (Equipment | null)[]; stack: number;
}

/** A complete heads-up table. Private choices only enter the public observation at reveal. */
export class NumericTable {
  readonly rng: Rng;
  readonly players: [Player, Player];
  phase = "draft";
  handNo = 1;
  dealer: Seat = 0;
  pot = 0;
  arenaId = "";
  ruleId = "";
  effects: { id: string; status: string }[] = [];
  private actors: Seat[] = [];
  private round = 1;
  private contributions = pair();
  private invested = pair();
  private target = 0;
  private acted = [false, false];
  private opDone = [false, false];
  private ops = pair();
  private checks = pair();
  private raises = pair();
  private roundPaid = false;
  private votes: (boolean | null)[] = [null, null];
  private bids: (number | null)[] = [null, null];
  private offers: [string[], string[]] = [[], []];
  private pending: ({ pos: number; equipment: Equipment } | null)[] = [null, null];
  private outcome: NumericObservation["result"] = null;

  constructor(opts: { seed?: number; buyIn?: number } = {}) {
    this.rng = new Rng(opts.seed ?? Date.now());
    const buy = opts.buyIn ?? 100;
    if (!Number.isSafeInteger(buy) || buy < 3) throw Error("起始筹码至少为 3，且须为整数");
    const player = (): Player => ({ numbers: [], current: [], seen: [], kept: [], rerolled: false, slots: null, equipment: [null, null, null], stack: buy });
    this.players = [player(), player()];
    this.startHand();
  }

  private startHand() {
    this.phase = "draft"; this.round = 1; this.actors = [...seats]; this.outcome = null;
    this.contributions = pair(); this.invested = pair(); this.ops = pair(); this.checks = pair(); this.raises = pair();
    this.target = 0; this.acted = [false, false]; this.opDone = [false, false]; this.roundPaid = false;
    this.offers = [[], []]; this.pending = [null, null]; this.votes = [null, null]; this.bids = [null, null];
    this.arenaId = this.rng.pick(NUMERIC_ARENAS).id;
    this.ruleId = this.rng.pick(NUMERIC_RULES).id;
    this.effects = this.rng.sample(NUMERIC_EFFECTS, 3).map(x => ({ id: x.id, status: "pending" }));
    // Equal antes avoid an unmatched side pot when one player has only one chip left.
    const ante = Math.min(2, ...this.players.map(p => p.stack));
    for (const s of seats) {
      const p = this.players[s];
      p.numbers = [this.rng.int(8) + 3, this.rng.int(8) + 3, this.rng.int(8) + 3];
      p.current = []; p.seen = []; p.kept = []; p.rerolled = false; p.slots = null; p.equipment = [null, null, null];
      this.draw(s); this.pay(s, ante);
    }
  }

  private draw(s: Seat) {
    const p = this.players[s];
    const pool = NUMERIC_CHARACTER_IDS.filter(x => !p.seen.includes(x));
    p.current = this.rng.sample(pool, Math.min(9, pool.length)); p.seen.push(...p.current);
  }
  private pay(s: Seat, amount: number) {
    const paid = Math.min(this.players[s].stack, amount);
    this.players[s].stack -= paid; this.pot += paid; this.invested[s] += paid;
    return paid;
  }
  private refundUnmatchedBet() {
    const diff = this.contributions[0] - this.contributions[1];
    const s: Seat = diff > 0 ? 0 : 1, refund = Math.abs(diff);
    this.players[s].stack += refund; this.pot -= refund; this.invested[s] -= refund; this.contributions[s] -= refund;
  }
  private canEquip(s: Seat) { return this.round <= 7 && this.players[s].stack > 0 && (this.round > 3 || this.players[s].equipment.some(x => !x)); }

  observe(s: Seat): NumericObservation {
    const p = this.players[s], f = this.players[other(s)];
    return {
      phase: this.phase, handNo: this.handNo, round: this.round, dealer: this.dealer,
      stacks: [this.players[0].stack, this.players[1].stack], pot: this.pot, toAct: [...this.actors],
      arenaId: this.arenaId, ruleId: this.ruleId, effects: this.effects.map(x => ({ ...x })),
      opFee: Math.min(2, p.stack), canEquip: this.canEquip(s), bidCap: Math.min(p.stack, 20),
      me: { numbers: [...p.numbers], current: [...p.current], kept: [...p.kept], rerolled: p.rerolled,
        slots: p.slots?.map(x => ({ ...x, equipment: x.equipment && { ...x.equipment } })) ?? null,
        equipment: p.equipment.map(x => x && { ...x }),
        offers: this.phase === "equip" && this.actors.includes(s) ? [...this.offers[s]] : null },
      opponent: { tiers: [...f.numbers].sort((a, b) => b - a).map(x => x <= 4 ? "低" : x >= 8 ? "高" : "中"), placed: !!f.slots, equipment: f.equipment.map(x => x && { ...x }) },
      betting: { toCall: Math.max(0, this.target - this.contributions[s]), minRaiseTo: this.target + 2, target: this.target, roundBet: [...this.contributions] },
      result: this.outcome ? structuredClone(this.outcome) : null,
    };
  }

  apply(s: Seat, a: NumericAction) {
    if (!this.actors.includes(s)) throw Error("请等待对手完成行动");
    const p = this.players[s];
    if (this.phase === "draft") {
      if (a.type === "keep") {
        const id = Number.isInteger(a.index) ? p.current[a.index] : undefined;
        if (!id || p.kept.length >= 3) throw Error("请选择一张候选人物");
        p.kept.push(id); p.current.splice(a.index, 1);
        if (p.kept.length === 3) { this.actors = this.actors.filter(x => x !== s); if (!this.actors.length) { this.phase = "place"; this.actors = [...seats]; } }
        return;
      }
      if (a.type === "reroll" && !p.rerolled) { p.rerolled = true; this.draw(s); return; }
      throw Error("请选择人物，或使用一次换牌");
    }
    if (this.phase === "place") {
      if (a.type !== "place") throw Error("请先确认三个位置");
      const permutation = (xs: number[]) => xs.length === 3 && new Set(xs).size === 3 && xs.every(x => Number.isInteger(x) && x >= 0 && x <= 2);
      if (!permutation(a.effects) || !permutation(a.numbers)) throw Error("数字和人物都需要各用一次");
      p.slots = a.numbers.map((n, i) => ({ number: p.numbers[n], effectId: p.kept[a.effects[i]], equipment: null }));
      this.actors = this.actors.filter(x => x !== s);
      if (!this.actors.length) { if (this.players.some(x => x.stack === 0)) this.allInResolve(); else this.betStart(); }
      return;
    }
    if (this.phase === "bet") return this.bet(s, a);
    if (this.phase === "operate") {
      if (a.type !== "operate") throw Error("请选择拿装备或跳过");
      if (a.draft) {
        if (!this.canEquip(s)) throw Error("当前没有可用的装备机会");
        this.pay(s, Math.min(2, p.stack)); this.ops[s]++; this.roundPaid = true;
        this.phase = "equip"; this.actors = [s];
        this.offers[s] = this.rng.sample([...new Set(NUMERIC_EQUIPMENT.map(x => x.id))], 3);
      } else { this.opDone[s] = true; this.operated(); }
      return;
    }
    if (this.phase === "equip") {
      if (a.type === "operate" && !a.draft) { this.offers[s] = []; this.opDone[s] = true; this.operated(); return; }
      if (a.type !== "equip") throw Error("请选择一件装备或放弃安装");
      const id = Number.isInteger(a.offerIndex) ? this.offers[s][a.offerIndex] : undefined;
      const slot = Number.isInteger(a.pos) ? p.slots?.[a.pos] : undefined;
      if (!id || !slot) throw Error("请选择有效的装备和位置");
      if (this.round <= 3 && slot.equipment) throw Error("普通装备只能装在空位");
      this.pending[s] = { pos: a.pos, equipment: { id, tier: this.tier() } };
      this.offers[s] = []; this.opDone[s] = true; this.operated(); return;
    }
    if (this.phase === "vote") {
      if (a.type !== "vote") throw Error("请选择是否启用这张额外效果");
      this.votes[s] = a.activate; this.actors = this.actors.filter(x => x !== s);
      if (!this.actors.length) {
        if (this.votes[0] === this.votes[1]) { this.effects[this.round - 1].status = this.votes[0] ? "active" : "inactive"; this.nextRound(); }
        else { this.phase = "bid"; this.actors = [...seats]; }
      }
      return;
    }
    if (this.phase === "bid") {
      if (a.type !== "bid" || !Number.isInteger(a.amount) || a.amount < 0 || a.amount > Math.min(20, p.stack)) throw Error(`请输入 0～${Math.min(20, p.stack)} 的整数出价`);
      this.bids[s] = a.amount; this.actors = this.actors.filter(x => x !== s);
      if (!this.actors.length) {
        this.pay(0, this.bids[0]!); this.pay(1, this.bids[1]!);
        const winner = this.bids[0] === this.bids[1] ? this.dealer : this.bids[0]! > this.bids[1]! ? 0 : 1;
        this.effects[this.round - 1].status = this.votes[winner] ? "active" : "inactive";
        if (this.players.some(x => x.stack === 0)) this.allInResolve(); else this.nextRound();
      }
      return;
    }
    if (this.phase === "result" && a.type === "nextHand") {
      this.handNo++; this.dealer = other(this.dealer); this.startHand(); return;
    }
    throw Error("此阶段不能执行该动作");
  }

  private bet(s: Seat, a: NumericAction) {
    const p = this.players[s], f = other(s), call = this.target - this.contributions[s];
    if (a.type === "fold") { this.settle({ winner: f, trace: [s === 0 ? "你弃牌，对手获得奖池。" : "对手弃牌，你获得奖池。"] }); return; }
    if (a.type === "check" || a.type === "call" || (a.type === "allIn" && p.stack <= call)) {
      if (a.type === "check" && call > 0) throw Error("对手已下注，请跟注、加注或弃牌");
      if (a.type !== "check" && call <= 0) throw Error("无需跟注，可以过牌");
      if (a.type === "check") this.checks[s]++;
      else { this.contributions[s] += this.pay(s, call); this.roundPaid = true; }
      this.acted[s] = true; this.betNext(s); return;
    }
    let to: number;
    if (a.type === "allIn") to = this.contributions[s] + p.stack;
    else if (a.type === "raise") to = a.to;
    else if (a.type === "bet" && this.target === 0) to = a.amount;
    else throw Error("请选择有效的下注动作");
    const all = to === this.contributions[s] + p.stack;
    if (!Number.isSafeInteger(to) || to <= this.target || to - this.contributions[s] > p.stack || (!all && to < this.target + 2)) throw Error(`至少加到 ${this.target + 2}，筹码不足时可全押`);
    this.contributions[s] += this.pay(s, to - this.contributions[s]); this.roundPaid = true; this.raises[s]++;
    this.target = to; this.acted[s] = true; this.acted[f] = false; this.actors = [f];
  }
  private betStart() {
    this.phase = "bet"; this.actors = [other(this.dealer)]; this.acted = [false, false];
    this.contributions = pair(); this.target = 0; this.opDone = [false, false]; this.pending = [null, null]; this.roundPaid = false;
  }
  private betNext(s: Seat) {
    if (!this.acted[other(s)]) { this.actors = [other(s)]; return; }
    if (this.players.some(x => x.stack === 0)) { this.refundUnmatchedBet(); this.allInResolve(); }
    else if (this.round > 7) { if (this.roundPaid) this.nextRound(); else this.resolve(); }
    else { this.phase = "operate"; this.actors = [...seats]; }
  }
  private tier(): Equipment["tier"] { return this.round <= 3 ? "normal" : this.round <= 5 ? "replace-1" : "replace-2"; }
  private operated() {
    this.phase = "operate"; this.actors = seats.filter(s => !this.opDone[s]);
    if (this.actors.length) return;
    // Publish both installations together, never the opponent's candidates or pending choice.
    for (const s of seats) {
      const next = this.pending[s];
      if (next) { this.players[s].equipment[next.pos] = { ...next.equipment }; this.players[s].slots![next.pos].equipment = { ...next.equipment }; }
    }
    this.pending = [null, null];
    if (this.players.some(x => x.stack === 0)) { this.allInResolve(); return; }
    if (this.round <= 3) { this.phase = "vote"; this.votes = [null, null]; this.bids = [null, null]; this.actors = [...seats]; }
    else if (!this.roundPaid) this.resolve();
    else this.nextRound();
  }
  private nextRound() { this.round++; this.betStart(); }
  private allInResolve() { this.effects.forEach(x => { if (x.status === "pending") x.status = "inactive"; }); this.resolve(); }
  private settle(result: NonNullable<NumericObservation["result"]>) {
    const won = this.pot, payouts: [number, number] = [0, 0];
    if (result.winner === null) { payouts[0] = Math.floor(won / 2); payouts[1] = Math.floor(won / 2); payouts[this.dealer] += won % 2; }
    else payouts[result.winner as Seat] = won;
    for (const s of seats) this.players[s].stack += payouts[s];
    this.pot = 0; this.outcome = { ...result, pot: won, payouts };
    this.phase = this.players.some(p => p.stack === 0) ? "over" : "result";
    this.actors = this.phase === "result" ? [0] : [];
  }
  private resolve() {
    const teams = this.players.map(p => ({ slots: p.slots! })) as [NumericTeam, NumericTeam];
    const stats = seats.map(s => ({ invested: this.invested[s], betOrRaise: this.raises[s], checks: this.checks[s], opsPaid: this.ops[s], stack: this.players[s].stack, round: this.round })) as Parameters<typeof runNumericResolution>[0]["stats"];
    const r = runNumericResolution({ teams, arenaId: this.arenaId, ruleId: this.ruleId, activeEffectIds: this.effects.filter(x => x.status === "active").map(x => x.id), stats });
    this.settle({ winner: r.winner, teams: teams.map(t => t.slots.map(x => ({ effectId: x!.effectId, number: x!.number, equipmentId: x!.equipment?.id ?? null }))), powers: r.powers, lineWinners: r.lineWinners, trace: r.trace, lines: r.lines });
  }
  aiAction(s: Seat): NumericAction | null {
    const o = this.observe(s);
    if (!o.toAct.includes(s)) return null;
    if (o.phase === "draft") return { type: "keep", index: 0 };
    if (o.phase === "place") return { type: "place", numbers: [0, 1, 2], effects: [0, 1, 2] };
    if (o.phase === "bet") return o.betting.toCall ? { type: "call" } : { type: "check" };
    if (o.phase === "operate") return { type: "operate", draft: this.canEquip(s) && this.players[s].equipment.some(x => !x) };
    if (o.phase === "equip") return { type: "equip", offerIndex: 0, pos: Math.max(0, this.players[s].equipment.findIndex(x => !x)) };
    if (o.phase === "vote") return { type: "vote", activate: this.rng.next() > .5 };
    if (o.phase === "bid") return { type: "bid", amount: Math.min(2, this.players[s].stack) };
    return null;
  }
}
