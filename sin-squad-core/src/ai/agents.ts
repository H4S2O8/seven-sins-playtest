import { runBattle } from "../battle/engine.js";
import { CHARACTERS, character } from "../content/characters.js";
import { PUBLIC_EFFECTS, RULES } from "../content/tables.js";
import type { Action, Aim } from "../game/actions.js";
import type { Table } from "../game/table.js";
import { legalActions, observe, type Observation } from "../game/view.js";
import { Rng } from "../rng.js";
import { other, type Seat, type SlotSetup, type TeamSetup } from "../types.js";

export interface Agent {
  readonly name: string;
  act(table: Table, seat: Seat): Action;
}

/** 随机合法动作（有过牌时不弃牌），作为基准对手。 */
export class RandomAgent implements Agent {
  readonly name = "随机";
  private readonly rng: Rng;
  constructor(seed = 7) {
    this.rng = new Rng(seed);
  }
  act(table: Table, seat: Seat): Action {
    let acts = legalActions(table, seat);
    if (acts.some((a) => a.type === "check")) acts = acts.filter((a) => a.type !== "fold");
    // 改指向有二十几种写法，只算一个选项，不然随机对手几乎每次都改指向
    const aims = acts.filter((a) => a.type === "operate" && a.aim);
    if (aims.length) acts = [...acts.filter((a) => !(a.type === "operate" && a.aim)), this.rng.pick(aims)];
    return this.rng.pick(acts);
  }
}

export type Style = "cautious" | "aggressive" | "bluff";

/**
 * 启发式对手：只读自己的观察，用战斗模拟估算胜率再决定。
 * 对手的暗置人物按“公开挑入的人物 + 全部人物”随机猜。
 */
export class HeuristicAgent implements Agent {
  readonly name: string;
  private readonly rng: Rng;
  constructor(readonly style: Style = "cautious", seed = 11, private readonly samples = 16) {
    this.rng = new Rng(seed);
    this.name = { cautious: "谨慎", aggressive: "激进", bluff: "爱诈唬" }[style];
  }

  act(table: Table, seat: Seat): Action {
    const obs = observe(table, seat);
    const acts = legalActions(table, seat);
    switch (obs.phase) {
      case "arena": return this.rng.pick(acts);
      case "place": return this.choosePlacement(obs, acts);
      case "peek": return acts[0].type === "peek" ? this.rng.pick(acts) : this.chooseSwap(obs, acts);
      case "reveal2": return this.chooseReveal2(obs, acts);
      case "bet": return this.chooseBet(obs, acts);
      case "operate": return this.chooseOperation(obs);
      case "draft": return this.chooseDraft(obs, acts);
      case "vote": return this.chooseVote(obs);
      case "bid": return this.chooseBid(obs, acts);
      case "marketPick": return this.rng.pick(acts);
      case "marketRemove": return acts[0];
      default: return acts[0];
    }
  }

  // ── 估算 ──

  /** 在当前公开信息下模拟若干场，返回本方胜率（平局算半场）。 */
  estimate(obs: Observation, mine?: TeamSetup, opts: { peActive?: boolean } = {}, n = this.samples): number {
    const me = mine ?? this.myTeam(obs);
    if (!me) return 0.5;
    return this.compare(obs, [me], opts, n)[0];
  }

  /** 同一批猜出来的对手、规则、效果下，分别算几支我方队伍的胜率（配对比较，差值比分开估算稳得多）。 */
  private compare(obs: Observation, mine: TeamSetup[], opts: { peActive?: boolean } = {}, n = this.samples): number[] {
    const score = mine.map(() => 0);
    for (let i = 0; i < n; i++) {
      const foe = this.guessFoe(obs);
      const ruleId = obs.ruleId ?? this.rng.pick(RULES).id;
      const peId = obs.publicEffectId
        ? (opts.peActive ?? obs.publicEffectActive ?? this.rng.next() < 0.5) ? obs.publicEffectId : null
        : this.rng.next() < 0.3 ? this.rng.pick(PUBLIC_EFFECTS).id : null;
      const arenaId = obs.arenaActive ? obs.arenaId ?? obs.arenaOptions[0] : "NONE";
      mine.forEach((me, k) => {
        const teams: [TeamSetup, TeamSetup] = obs.seat === 0 ? [me, foe] : [foe, me];
        const r = runBattle({
          teams, ruleId, arenaId, publicEffectId: peId, pot: obs.pot, firstSeat: other(obs.dealer),
          campaign: obs.battleRules ?? undefined,
        });
        score[k] += r.winner === obs.seat ? 1 : r.winner === null ? 0.5 : 0;
      });
    }
    return score.map((s) => s / n);
  }

  private myTeam(obs: Observation): TeamSetup | null {
    const p = obs.me.placement;
    if (!p) return null;
    const slots: SlotSetup[] = p.slots.map((c, i) => ({ characterId: c, equipmentId: c ? obs.me.equipment[i] : null, aim: obs.me.aim[i] }));
    return { slots, eat: null, bet: this.betCtx(obs, obs.seat, p.reveal) };
  }

  private betCtx(obs: Observation, seat: Seat, revealedPos: number) {
    return {
      invested: obs.invested[seat],
      betOrRaiseCount: obs.betting.betOrRaiseCount[seat],
      checkCount: obs.betting.checkCount[seat],
      opsPaid: obs.betting.opsPaid[seat],
      revealedPos,
      stack: obs.stacks[seat],
    };
  }

  private guessFoe(obs: Observation): TeamSetup {
    const o = obs.opponent;
    const pool = [...o.publicPicks, ...CHARACTERS.map((c) => c.id)];
    const slots: SlotSetup[] = [0, 1, 2].map((pos) => {
      if (o.emptyPositions.includes(pos)) return { characterId: null, equipmentId: null };
      let id: string;
      if (o.revealed && o.revealed.pos === pos) id = o.revealed.characterId;
      else if (o.revealed2 && o.revealed2.pos === pos) id = o.revealed2.characterId;
      else if (obs.me.peek && obs.me.peek.pos === pos) id = obs.me.peek.characterId;
      else id = this.rng.pick(pool);
      return { characterId: id, equipmentId: o.equipment[pos], aim: o.aim[pos] };
    });
    return { slots, eat: null, bet: this.betCtx(obs, other(obs.seat), o.revealed?.pos ?? 0) };
  }

  // ── 各阶段 ──

  private choosePlacement(obs: Observation, acts: Action[]): Action {
    const candidates = this.rng.sample(acts, Math.min(12, acts.length));
    let best = candidates[0];
    let bestScore = -1;
    for (const a of candidates) {
      if (a.type !== "place") continue;
      const slots = a.picks.map((i) => obs.me.dealt[i]) as (string | null)[];
      const team: TeamSetup = {
        slots: slots.map((c) => ({ characterId: c, equipmentId: null })),
        eat: a.eat,
        bet: this.betCtx(obs, obs.seat, a.reveal),
      };
      const s = this.estimate(obs, team, {}, 6);
      if (s > bestScore) { bestScore = s; best = a; }
    }
    return best;
  }

  /**
   * 拿装备：有操作费、而且付得起（不超过 10 或四分之一筹码里较多的那个）就拿。
   * 改指向不花钱，另外算：试“全队集火某一个位置”和“都打对位”，和现在的指向放在同一批猜出来的对手里比，
   * 胜率高出 4 个百分点才改（门槛挡掉估算的噪声）。
   */
  private chooseOperation(obs: Observation): Action {
    const draft = obs.opFee > 0 && obs.opFee <= Math.max(10, obs.stacks[obs.seat] * 0.25);
    const aim = this.chooseAim(obs);
    return aim ? { type: "operate", draft, aim } : { type: "operate", draft };
  }

  private chooseAim(obs: Observation): Aim | null {
    const base = this.myTeam(obs)!;
    const cur = obs.me.aim;
    const same = (a: Aim, b: Aim) => a.every((x, i) => x === b[i]);
    const options = ([[0, 1, 2]] as Aim[])
      .concat([0, 1, 2].filter((p) => !obs.opponent.emptyPositions.includes(p)).map((p): Aim => [p, p, p]))
      .filter((aim) => !same(aim, cur));
    if (!options.length) return null;
    const withAim = (aim: Aim): TeamSetup => ({ ...base, slots: base.slots.map((s, i) => ({ ...s, aim: aim[i] })) });
    const [now, ...alt] = this.compare(obs, [base, ...options.map(withAim)], {}, 24);
    const best = alt.indexOf(Math.max(...alt));
    return alt[best] - now >= 0.04 ? options[best] : null;
  }

  private chooseBet(obs: Observation, acts: Action[]): Action {
    const p = this.estimate(obs);
    const has = (t: Action["type"]) => acts.find((a) => a.type === t);
    const sized = acts.filter((a) => a.type === "bet" || a.type === "raise");
    const toCall = obs.betting.toCall;
    const potOdds = toCall / (obs.pot + toCall || 1);
    const bluffing = this.style === "bluff" && this.rng.next() < 0.25;
    const strong = this.style === "aggressive" ? 0.55 : 0.62;

    if ((p > strong || bluffing) && sized.length) {
      const pick = p > 0.75 || bluffing ? sized[Math.min(sized.length - 1, 1)] : sized[0];
      return pick;
    }
    if (toCall === 0) return has("check") ?? acts[0];
    if (p >= potOdds + (this.style === "cautious" ? 0.05 : -0.05)) return has("call") ?? has("allIn")!;
    return has("fold") ?? has("call") ?? acts[0];
  }

  /**
   * 第二次翻开：把强的留到最后，先翻弱的（攻 × 血最小）。
   * 爱诈唬的有三成反过来先翻强的，让对手以为后面还有更强的。
   */
  private chooseReveal2(obs: Observation, acts: Action[]): Action {
    const power = (a: Action) => {
      if (a.type !== "reveal2") return 0;
      const c = character(obs.me.placement!.slots[a.pos]!);
      return c.atk * c.hp;
    };
    const sorted = acts.slice().sort((a, b) => power(a) - power(b));
    return this.style === "bluff" && this.rng.next() < 0.3 ? sorted[sorted.length - 1] : sorted[0];
  }

  /** 偷看之后：试每一种换位（包括不换），挑估算胜率最高的。 */
  private chooseSwap(obs: Observation, acts: Action[]): Action {
    const base = this.myTeam(obs)!;
    let best = acts[0];
    let bestScore = -1;
    for (const a of acts) {
      if (a.type !== "peekSwap") continue;
      const team: TeamSetup = { ...base, slots: base.slots.map((s) => ({ ...s })) };
      if (a.swap) {
        const [x, y] = a.swap;
        [team.slots[x], team.slots[y]] = [team.slots[y], team.slots[x]];
      }
      const s = this.estimate(obs, team, {}, 8);
      if (s > bestScore) { bestScore = s; best = a; }
    }
    return best;
  }

  private chooseDraft(obs: Observation, acts: Action[]): Action {
    const base = this.myTeam(obs)!;
    let best = acts[0];
    let bestScore = -1;
    for (const a of acts) {
      if (a.type !== "draft") continue;
      const team: TeamSetup = { ...base, slots: base.slots.map((s) => ({ ...s })) };
      team.slots[a.pos].equipmentId = obs.me.offers![a.offerIndex];
      const s = this.estimate(obs, team, {}, 4);
      if (s > bestScore) { bestScore = s; best = a; }
    }
    return best;
  }

  private chooseVote(obs: Observation): Action {
    const on = this.estimate(obs, undefined, { peActive: true }, 10);
    const off = this.estimate(obs, undefined, { peActive: false }, 10);
    return { type: "vote", activate: on >= off };
  }

  private chooseBid(obs: Observation, acts: Action[]): Action {
    const want = obs.me.vote!;
    const on = this.estimate(obs, undefined, { peActive: true }, 10);
    const off = this.estimate(obs, undefined, { peActive: false }, 10);
    const gain = Math.max(0, want ? on - off : off - on);
    const value = gain * (obs.pot + 20);
    let best = acts[0];
    for (const a of acts) if (a.type === "bid" && a.amount <= value) best = a;
    return best;
  }
}

/** 让两个对手打完一整张牌桌（或打到手数上限）。 */
export function playTable(table: Table, agents: [Agent, Agent], maxHands = 60, maxSteps = 20000): void {
  let steps = 0;
  while (table.phase !== "over" && table.handNo <= maxHands) {
    if (++steps > maxSteps) throw new Error("步数超限，可能卡住了");
    const seats = table.toAct();
    if (seats.length === 0) throw new Error(`没有人需要行动（阶段：${table.phase}）`);
    for (const s of seats) {
      if (!table.toAct().includes(s)) continue;
      table.apply(s, agents[s].act(table, s));
    }
  }
}
