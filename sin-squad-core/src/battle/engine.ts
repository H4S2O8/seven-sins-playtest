import { character } from "../content/characters.js";
import { equipment } from "../content/tables.js";
import { other, type BetContext, type Seat, type TeamSetup } from "../types.js";
import {
  armorOf, emptyUnit, health, MAX_BARRIER, round1, snapshot, unitFrom,
  type Unit, type UnitSnapshot,
} from "./unit.js";
import { roundEndClaims, setupVictory, timeoutWinner, type VictoryState } from "./victory.js";

/**
 * 回合制战斗。完全确定：同样的输入永远得到同样的结果。
 *
 * 每轮：确定出手者和目标 → 守护改写目标 → 连击分两段 → 屏障挡段、护甲减段
 * → 双方同时扣血 → 吸血 → 轮末效果 → 移除倒下的人 → 触发“有人倒下”的能力 → 判定胜负。
 */

export interface BattleInput {
  teams: [TeamSetup, TeamSetup];
  ruleId: string;
  arenaId: string;
  /** 本手生效的公共效果；没有生效则为 null。 */
  publicEffectId: string | null;
  /** 本手奖池（赌徒酒窖用）。 */
  pot: number;
}

export type BattleEvent =
  | { round: number; type: "attack"; seat: Seat; pos: number; targetSeat: Seat; targetPos: number; segments: number[] }
  | { round: number; type: "blocked"; seat: Seat; pos: number }
  | { round: number; type: "damage"; seat: Seat; pos: number; amount: number; hpAfter: number }
  | { round: number; type: "heal"; seat: Seat; pos: number; amount: number }
  | { round: number; type: "switch"; seat: Seat; pos: number; remaining: number }
  | { round: number; type: "death"; seat: Seat; pos: number }
  | { round: number; type: "note"; text: string };

export interface BattleResult {
  /** null = 平局。 */
  winner: Seat | null;
  reason: "达成规则" | "同时达成·比伤害" | "到时比较" | "平局";
  rounds: number;
  events: BattleEvent[];
  final: [UnitSnapshot[], UnitSnapshot[]];
  /** 每一轮结束后的快照，给回放用。 */
  timeline: Array<[UnitSnapshot[], UnitSnapshot[]]>;
}

export function runBattle(input: BattleInput): BattleResult {
  return new Battle(input).run();
}

class Battle {
  private readonly teams: [Unit[], Unit[]];
  private readonly env: Set<string>;
  private readonly bet: [BetContext, BetContext];
  private readonly events: BattleEvent[] = [];
  private readonly timeline: Array<[UnitSnapshot[], UnitSnapshot[]]> = [];
  private readonly victory: VictoryState;
  private readonly maxRounds: number;
  private round = 0;
  private firstDeathDone: [boolean, boolean] = [false, false];
  private loneTriggered: [boolean, boolean] = [false, false];
  private wingUsed: [boolean, boolean] = [false, false];

  constructor(private readonly input: BattleInput) {
    this.env = new Set([input.arenaId, ...(input.publicEffectId ? [input.publicEffectId] : [])]);
    this.bet = [input.teams[0].bet, input.teams[1].bet];
    this.teams = [this.buildTeam(0), this.buildTeam(1)];
    this.setupBattle();
    this.victory = setupVictory(input.ruleId, this.teams, [this.bet[0].revealedPos, this.bet[1].revealedPos]);
    this.maxRounds = maxRoundsFor(input.ruleId);
  }

  // ───────────────────────── 开战前 ─────────────────────────

  private has(id: string) {
    return this.env.has(id);
  }

  /** 静默书库：第 1 轮所有人物能力失效，开战时能力也不发动。 */
  private abilityOn(u: Unit, name: string): boolean {
    if (!u.def || u.def.name !== name) return false;
    if (this.has("A08") && this.round <= 1) return false;
    return true;
  }

  private buildTeam(seat: Seat): Unit[] {
    const setup = this.input.teams[seat];
    const team = setup.slots.map((s, pos) =>
      s.characterId ? unitFrom(character(s.characterId), seat, pos) : emptyUnit(seat, pos),
    );
    team.forEach((u, i) => {
      const e = setup.slots[i].equipmentId;
      if (u.exists && e) u.equipmentIds.push(e);
    });
    if (setup.eat) {
      const eater = team[setup.eat.eater];
      const eaten = team[setup.eat.eaten];
      if (!eater.def || eater.def.name !== "饕餮" || !eaten.exists || eater === eaten) {
        throw new Error("非法的吞噬：只有饕餮能吞掉一名在场队友");
      }
      eater.atk += eaten.def!.atk;
      eater.hp += eaten.def!.hp;
      team[setup.eat.eaten] = emptyUnit(seat, setup.eat.eaten);
    }
    return team;
  }

  private setupBattle() {
    const [A, B] = this.teams;
    const all = [...A, ...B].filter((u) => u.exists);
    const startAbilities = !this.has("A08");
    const opp = (u: Unit) => this.teams[other(u.seat)][u.pos];

    // 夺装者：同时拿走对位的装备
    if (startAbilities) {
      const before = new Map(all.map((u) => [u, u.equipmentIds.slice()]));
      for (const u of all) {
        const o = opp(u);
        if (u.def?.name === "夺装者" && o.exists) {
          u.equipmentIds.push(...before.get(o)!);
          o.equipmentIds = o.equipmentIds.filter((id) => !before.get(o)!.includes(id));
        }
      }
    }
    for (const u of all) for (const id of u.equipmentIds) this.applyEquipment(u, id);

    // 下注层能力
    if (startAbilities) {
      for (const seat of [0, 1] as Seat[]) {
        const me = this.bet[seat];
        const foe = this.bet[other(seat)];
        for (const u of this.teams[seat].filter((x) => x.exists)) {
          switch (u.def!.name) {
            case "挑衅者": u.atk += 2 * foe.betOrRaiseCount; break;
            case "金主": { const k = Math.min(4, Math.floor(me.invested / 10)); u.atk += k; u.hp += 2 * k; break; }
            case "盾税官": this.addBarrier(u, Math.min(2, me.opsPaid), false); break;
            case "瞌睡客": u.hp += 6 * me.checkCount; break;
            case "沉眠巨像": u.atk += 2 * me.checkCount; break;
            case "炫耀者": if (me.revealedPos === u.pos) { u.atk += 2; u.hp += 6; } break;
          }
        }
        if (me.opsPaid === 0 && this.teams[seat].some((u) => u.exists && u.def!.name === "静息药师")) {
          for (const u of this.teams[seat]) if (u.exists) u.hp += 8;
        }
      }
      // 摹拳客：看的是对位此刻的攻和形状
      const copy = all.filter((u) => u.def!.name === "摹拳客" && opp(u).exists).map((u) => [u, opp(u).atk, opp(u).shape] as const);
      for (const [u, atk, shape] of copy) { u.atk = Math.max(u.atk, atk); u.shape = shape; }
    }

    // 场地的开战效果
    for (const team of this.teams) {
      const here = team.filter((u) => u.exists);
      if (here.length === 0) continue;
      if (this.has("A19")) { const lo = minBy(here, (u) => u.hp); lo.atk += 2; lo.hp += 4; }
      if (this.has("A20")) { const hi = maxBy(here, (u) => u.atk); hi.atk = Math.max(0, hi.atk - 3); }
      if (this.has("A13")) for (const u of here) u.atk += Math.floor(this.input.pot / 40);
      if (this.has("A22")) { const avg = Math.floor(here.reduce((s, u) => s + u.hp, 0) / here.length); for (const u of here) u.hp = avg; }
      if (this.has("A14")) for (const u of here) this.addBarrier(u, 1, false);
      if (this.has("A16")) this.addBarrier(maxBy(here, (u) => u.atk), 1, false);
      if (this.has("P02")) for (const u of here) u.armorBase += 2;
    }
    for (const u of all) { u.startHp = u.hp; u.maxHp = u.hp; }
    // 开场审判是开战后的伤害，不改变开战血量
    if (this.has("P29")) {
      for (const team of this.teams) {
        const here = team.filter((u) => u.exists);
        if (here.length) maxBy(here, (u) => armorOf(u)).hp -= 4;
      }
    }

    // 缔结、魅惑、沉眠
    for (const u of all) {
      const o = opp(u);
      if (u.def!.name === "沉眠巨像") u.skipRounds = 2;
      if (!startAbilities || !o.exists) continue;
      if (u.def!.name === "牵线人") { u.bonded = true; o.bonded = true; }
      if (u.def!.name === "魅惑者") o.charmed = true;
    }

    // 屏障回声：开战就带屏障的人也算“第一次获得”
    if (this.has("P08")) for (const u of all) if (u.barrier > 0) this.echoBarrier(u);
  }

  private applyEquipment(u: Unit, id: string) {
    const e = equipment(id).effect;
    switch (e.kind) {
      case "stat": u.atk += e.atk; u.hp += e.hp; u.eqAtk += e.atk; u.eqHp += e.hp; break;
      case "shape": u.shape = e.shape; u.atk += e.atk; u.eqAtk += e.atk; break;
      case "armor": u.armorEquip += e.armor; u.hp += e.hp; u.eqHp += e.hp; break;
      case "barrier": u.barrier = Math.min(MAX_BARRIER, u.barrier + e.barrier); u.atk += e.atk; u.eqAtk += e.atk; break;
    }
  }

  private addBarrier(u: Unit, n: number, echo = true) {
    if (n <= 0 || !u.alive) return;
    u.barrier = Math.min(MAX_BARRIER, u.barrier + n);
    if (echo && this.has("P08")) this.echoBarrier(u);
  }

  /** 屏障回声：第一次获得屏障时，队友各得一层；由回声得到的不再连锁。 */
  private echoBarrier(u: Unit) {
    if (u.barrierEchoed) return;
    u.barrierEchoed = true;
    for (const t of this.teams[u.seat]) {
      if (t !== u && t.alive) {
        t.barrierEchoed = true;
        t.barrier = Math.min(MAX_BARRIER, t.barrier + 1);
      }
    }
  }

  // ───────────────────────── 战斗 ─────────────────────────

  run(): BattleResult {
    for (this.round = 1; this.round <= this.maxRounds; this.round++) {
      const dealt = this.playRound();
      this.timeline.push([this.teams[0].map(snapshot), this.teams[1].map(snapshot)]);
      const claims = roundEndClaims(this.victory, this.teams, this.round);
      if (claims[0] || claims[1]) {
        if (claims[0] && claims[1]) {
          const d = dealt[0] - dealt[1];
          if (Math.abs(d) < 1e-9) return this.finish(null, "平局");
          return this.finish(d > 0 ? 0 : 1, "同时达成·比伤害");
        }
        return this.finish(claims[0] ? 0 : 1, "达成规则");
      }
    }
    this.round = this.maxRounds;
    const w = timeoutWinner(this.victory, this.teams);
    return this.finish(w, w === null ? "平局" : "到时比较");
  }

  private finish(winner: Seat | null, reason: BattleResult["reason"]): BattleResult {
    return {
      winner, reason, rounds: this.round, events: this.events, timeline: this.timeline,
      final: [this.teams[0].map(snapshot), this.teams[1].map(snapshot)],
    };
  }

  private alive(seat: Seat) {
    return this.teams[seat].filter((u) => u.alive);
  }

  /** 进行一轮，返回双方这一轮造成的总伤害（平局决胜用）。 */
  private playRound(): [number, number] {
    const r = this.round;

    // 轮初效果
    if (this.has("P06") && (r === 2 || r === 4 || r === 6)) {
      for (const seat of [0, 1] as Seat[]) {
        const al = this.alive(seat);
        if (al.length) this.addBarrier(minBy(al, health), 1);
      }
    }
    if (this.has("P30") && r === 3) {
      for (const u of [...this.alive(0), ...this.alive(1)]) if (u.lostTotal === 0) this.addBarrier(u, 1);
    }

    // 1. 确定出手者和目标
    interface Attack { a: Unit; t: Unit; opposite: boolean; no: number }
    const attacks: Attack[] = [];
    for (const seat of [0, 1] as Seat[]) {
      const actors = this.alive(seat);
      const lowest = actors.length ? minBy(actors, (u) => u.hp) : null;
      for (const u of actors) {
        if (u.bonded) continue;
        if (r <= u.skipRounds) continue;
        if (this.has("A06") && r === 1) continue;
        if (this.has("A21") && r === 1 && u !== lowest) continue;
        if (u.skipNext) { u.skipNext = false; continue; }

        let target: Unit | null = null;
        let opposite = false;
        const o = this.teams[other(seat)][u.pos];
        if (u.charmed && r === 1) {
          const adj = this.teams[seat].filter((x) => x.alive && Math.abs(x.pos - u.pos) === 1);
          if (adj.length) target = minBy(adj, (x) => x.hp);
        }
        if (!target) {
          if (o.alive) {
            target = o;
            opposite = true;
          } else {
            if (u.switchRemaining === null) u.switchRemaining = this.switchCost(u.pos);
            if (u.switchRemaining > 0) {
              u.switchRemaining--;
              u.switched = true;
              this.events.push({ round: r, type: "switch", seat, pos: u.pos, remaining: u.switchRemaining });
              continue;
            }
            u.switched = true;
            const foes = this.alive(other(seat));
            if (!foes.length) continue;
            target = minBy(foes, (x) => x.hp);
          }
        }
        const times = this.has("P13") && r === 4 && u.attacks < 3 ? 2 : 1;
        for (let k = 0; k < times; k++) attacks.push({ a: u, t: target, opposite, no: 0 });
      }
    }

    // 2. 守护改写目标
    for (const atk of attacks) {
      if (atk.t.seat === atk.a.seat) continue;
      const guards = this.teams[atk.t.seat].filter(
        (g) => g.alive && g !== atk.t && Math.abs(g.pos - atk.t.pos) === 1 && this.abilityOn(g, "同行药袋"),
      );
      if (guards.length) { atk.t = guards[0]; atk.opposite = false; }
    }

    // 集火回响：同一轮被两人以上攻击，先得一层屏障
    if (this.has("P14")) {
      const by = new Map<Unit, Set<Unit>>();
      for (const { a, t } of attacks) if (a.seat !== t.seat) (by.get(t) ?? by.set(t, new Set()).get(t)!).add(a);
      for (const [t, set] of by) if (set.size >= 2 && !t.focusEchoUsed) { t.focusEchoUsed = true; this.addBarrier(t, 1); }
    }

    // 3. 算出每次攻击的伤害并拆段
    /** 一次攻击：护甲按段减到 0 为止，但整次攻击只要有一段打中，至少扣 1。 */
    interface Hit { a: Unit; t: Unit; sum: number; landed: boolean; minOne: boolean }
    interface Seg { a: Unit; t: Unit; amount: number; hit: Hit }
    const segs: Seg[] = [];
    const hitList: Hit[] = [];
    for (const atk of attacks) {
      const { a, t, opposite } = atk;
      atk.no = ++a.attacks;
      let d = a.atk + a.pendingBonus;
      a.pendingBonus = 0;
      if (a.huntTarget === t) { d += 2; a.huntTarget = null; }
      if (this.has("P10") && r === 1) d += 2;
      if (this.has("P16") && opposite) d += 1;
      if (this.has("A05") && opposite) d += 1;
      if (this.has("P18") && r >= 5) d += 1;
      if (this.has("A01") && a.switched && !opposite) d = Math.max(1, d - 2);
      if (this.has("P23") && health(a) < 0.3) d += Math.max(1, Math.floor(d * 0.25));
      if (this.abilityOn(a, "无瑕刺客") && a.hp >= a.maxHp) d *= 2;
      if (this.abilityOn(a, "清算者") && r === 1 && this.bet[other(a.seat)].betOrRaiseCount > 0) d *= 2;
      if (this.has("P11") && (atk.no === 3 || atk.no === 6)) d *= 2;
      if (this.has("P26") && a.pos === 1) d = Math.floor(d * 1.25 * 2) / 2;
      const parts = a.shape === "multi" ? [d / 2, d / 2] : [d];
      this.events.push({ round: r, type: "attack", seat: a.seat, pos: a.pos, targetSeat: t.seat, targetPos: t.pos, segments: parts });
      const hit: Hit = { a, t, sum: 0, landed: false, minOne: true };
      hitList.push(hit);
      for (const p of parts) segs.push({ a, t, amount: p, hit });
      if (this.has("P09") && r >= 3) {
        // 深夜霜降：独立的一段 1 点伤害，护甲可以挡掉
        const frost: Hit = { a, t, sum: 0, landed: false, minOne: false };
        hitList.push(frost);
        segs.push({ a, t, amount: 1, hit: frost });
      }
    }
    // 屏障按攻击者位置 1→2→3 的顺序决定哪一段先到
    segs.sort((x, y) => x.a.pos - y.a.pos || x.a.seat - y.a.seat);

    // 4. 结算每一段（先记账，最后同时扣血）
    const dmg = new Map<Unit, number>();
    const dealt = new Map<Unit, number>();
    const hits = new Map<Unit, number>();
    const hitters = new Map<Unit, Set<Unit>>();
    const armorBreaks = new Map<Unit, number>();
    const add = <K>(m: Map<K, number>, k: K, v: number) => m.set(k, (m.get(k) ?? 0) + v);

    for (const s of segs) {
      const { a, t } = s;
      if (t.barrier > 0) {
        t.barrier--;
        this.events.push({ round: r, type: "blocked", seat: t.seat, pos: t.pos });
        this.onBarrierBroken(t, a, dmg);
        continue;
      }
      let armor = armorOf(t);
      if (this.has("P04") && health(t) > 0.75) armor = Math.floor(armor / 2);
      let real = Math.max(0, s.amount - armor);
      s.hit.landed = true;
      if (this.has("A07") && t.attacks === 0) real /= 2;
      if (this.has("A09") && r <= 2) real = Math.min(real, t.startHp / 4);
      if (this.has("P26") && t.pos === 1) real *= 1.25;
      if (this.has("P27") && t.pos !== 1 && a.pos === 1 && a.seat !== t.seat && !t.sideCoverUsed) { t.sideCoverUsed = true; real /= 2; }
      real = round1(real);
      s.hit.sum += real;
      if (real <= 0) continue;
      add(dmg, t, real);
      add(dealt, a, real);
      add(hits, t, 1);
      (hitters.get(t) ?? hitters.set(t, new Set()).get(t)!).add(a);
      if (this.has("P03") && real >= 6) add(armorBreaks, t, 1);
      if (this.has("P12") && real >= 8) a.skipNext = true;
      if (this.has("A10")) {
        for (const x of this.teams[t.seat]) if (x.alive && Math.abs(x.pos - t.pos) === 1) add(dmg, x, 1);
      }
    }

    // 每次攻击至少扣 1（被屏障整段挡掉的不算打中）
    for (const h of hitList) {
      if (!h.landed || !h.minOne || h.sum >= 1) continue;
      const top = round1(1 - h.sum);
      if (h.sum === 0) {
        add(hits, h.t, 1);
        (hitters.get(h.t) ?? hitters.set(h.t, new Set()).get(h.t)!).add(h.a);
      }
      add(dmg, h.t, top);
      add(dealt, h.a, top);
    }

    // 5. 同时扣血
    for (const [u, v] of dmg) this.loseHp(u, v);

    // 6. 吸血、蓄痛、疗愈震波、裂甲
    for (const [u, v] of dealt) {
      if (u.hp <= 0 || !this.abilityOn(u, "嚼盾兽")) continue;
      let heal = v;
      if (this.has("P19")) heal /= 2;
      if (this.has("P18") && r >= 5) heal /= 2;
      this.heal(u, heal);
    }
    for (const [u, n] of hits) if (u.hp > 0 && this.abilityOn(u, "蓄痛拳手")) u.atk += n;
    for (const [u, n] of armorBreaks) u.armorBase = Math.max(0, u.armorBase - n);

    // 7. 攻击带来的自损
    for (const { a, no } of attacks) {
      if (this.has("A12") && no % 3 === 0) this.loseHp(a, 4);
      if (this.has("P22") && (no === 2 || no === 4 || no === 6)) { this.loseHp(a, 2); a.pendingBonus += 3; }
    }

    // 8. 轮末效果
    if (this.has("A11") && (r === 2 || r === 4 || r === 6)) for (const u of this.livingAll()) this.loseHp(u, 2);
    if (this.has("A15") && (r === 3 || r === 6)) for (const u of this.livingAll()) u.armorBase = Math.max(0, u.armorBase - 1);
    if (this.has("P24")) for (const u of this.livingAll()) if (u.regenRounds > 0 && u.hp > 0) { u.regenRounds--; this.heal(u, 2); }

    // 9. 移除倒下的人，并处理“有人倒下”
    this.resolveDeaths(hitters);

    const sum = (seat: Seat) => [...dealt].filter(([u]) => u.seat === seat).reduce((s, [, v]) => s + v, 0);
    return [sum(0), sum(1)];
  }

  private switchCost(pos: number): number {
    if (this.has("A02")) return 0;
    if (this.has("A03")) return 2;
    if (this.has("A04")) return pos === 0 ? 2 : pos === 2 ? 0 : 1;
    return 1;
  }

  private livingAll() {
    return [...this.teams[0], ...this.teams[1]].filter((u) => u.alive && u.hp > 0);
  }

  private loseHp(u: Unit, v: number) {
    if (v <= 0 || !u.alive) return;
    u.hp = round1(u.hp - v);
    u.lostTotal += v;
    this.events.push({ round: this.round, type: "damage", seat: u.seat, pos: u.pos, amount: round1(v), hpAfter: u.hp });
    if (this.has("P21") && u.hp > 0) {
      u.bloodSpringAcc += v;
      while (u.bloodSpringAcc >= 8) { u.bloodSpringAcc -= 8; this.heal(u, 2); }
    }
  }

  private heal(u: Unit, v: number) {
    if (v <= 0 || u.hp <= 0) return;
    const room = u.maxHp - u.hp;
    const real = round1(Math.min(room, v));
    if (real > 0) {
      u.hp = round1(u.hp + real);
      this.events.push({ round: this.round, type: "heal", seat: u.seat, pos: u.pos, amount: real });
    }
    if (this.has("P20") && v - real > 0 && u.barrier < 1) this.addBarrier(u, 1);
    if (this.has("P25") && real > 0) {
      u.healAcc += real;
      while (u.healAcc >= 6) {
        u.healAcc -= 6;
        const o = this.teams[other(u.seat)][u.pos];
        if (o.alive) this.loseHp(o, 2);
      }
    }
  }

  private onBarrierBroken(t: Unit, attacker: Unit, dmg: Map<Unit, number>) {
    if (this.has("P01")) t.pendingBonus += 3;
    if (this.has("P05")) dmg.set(t, (dmg.get(t) ?? 0) + 1);
    if (this.has("P07") && attacker.seat !== t.seat) dmg.set(t, (dmg.get(t) ?? 0) + 2);
    if (this.has("P28") && t.pos !== 1 && !this.wingUsed[t.seat]) {
      const otherWing = this.teams[t.seat][t.pos === 0 ? 2 : 0];
      if (otherWing.alive && t.alive) { this.wingUsed[t.seat] = true; this.addBarrier(otherWing, 1); }
    }
  }

  private resolveDeaths(hitters: Map<Unit, Set<Unit>>) {
    const r = this.round;
    let newlyDead = [...this.teams[0], ...this.teams[1]].filter((u) => u.alive && u.hp <= 0);
    for (const u of newlyDead) { u.alive = false; u.deathRound = r; }

    // 碎裂终章：只触发一次，不连锁
    if (this.has("P31") && r >= 5) {
      for (const u of newlyDead) {
        const o = this.teams[other(u.seat)][u.pos];
        if (o.alive) this.loseHp(o, 4);
      }
      const extra = [...this.teams[0], ...this.teams[1]].filter((u) => u.alive && u.hp <= 0);
      for (const u of extra) { u.alive = false; u.deathRound = r; }
      newlyDead = [...newlyDead, ...extra];
    }
    for (const u of newlyDead) this.events.push({ round: r, type: "death", seat: u.seat, pos: u.pos });

    if (newlyDead.length) {
      for (const u of this.livingAll()) {
        if (this.abilityOn(u, "残羹客")) {
          const n = newlyDead.length;
          u.atk += 2 * n; u.hp += 4 * n; u.maxHp += 4 * n;
        }
      }
      for (const v of newlyDead) {
        for (const k of hitters.get(v) ?? []) {
          if (k.alive && k.seat !== v.seat && this.abilityOn(k, "收藏家")) {
            k.atk += 2 + v.eqAtk; k.hp += v.eqHp; k.maxHp += v.eqHp;
          }
        }
      }
      for (const seat of [0, 1] as Seat[]) {
        if (this.firstDeathDone[seat] || !newlyDead.some((u) => u.seat === seat)) continue;
        this.firstDeathDone[seat] = true;
        for (const u of this.alive(seat)) {
          if (this.has("A18")) this.addBarrier(u, 1);
          if (this.has("P15")) u.pendingBonus += 2;
        }
      }
    }
    if (this.has("P24")) {
      for (const seat of [0, 1] as Seat[]) {
        const al = this.alive(seat);
        if (al.length === 1 && !this.loneTriggered[seat]) {
          this.loneTriggered[seat] = true;
          this.addBarrier(al[0], 1);
          al[0].regenRounds = 2;
        }
      }
    }
    if (this.has("A17")) {
      for (const u of this.livingAll()) if (!u.halfHealthTriggered && health(u) <= 0.5) { u.halfHealthTriggered = true; this.addBarrier(u, 1); }
    }
    if (this.has("P17")) {
      for (const [t, set] of hitters) {
        if (!t.alive || health(t) > 0.25) continue;
        for (const a of set) if (!a.huntUsed && a.seat !== t.seat) { a.huntUsed = true; a.huntTarget = t; }
      }
    }
  }
}

function minBy<T>(items: T[], f: (x: T) => number): T {
  let best = items[0];
  for (const x of items) if (f(x) < f(best)) best = x;
  return best;
}

function maxBy<T>(items: T[], f: (x: T) => number): T {
  let best = items[0];
  for (const x of items) if (f(x) > f(best)) best = x;
  return best;
}

export function maxRoundsFor(ruleId: string): number {
  switch (ruleId) {
    case "V19": return 3;
    case "V20": return 12;
    case "V21": case "V22": case "V23": case "V24": return 4;
    case "V25": case "V26": case "V27": return 5;
    default: return 8;
  }
}
