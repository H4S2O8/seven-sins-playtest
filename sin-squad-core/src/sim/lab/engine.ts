import { character } from "../../content/characters.js";
import { equipment } from "../../content/tables.js";
import { other, type BetContext, type CharacterDef, type Seat, type TeamSetup } from "../../types.js";
import {
  armorOf, emptyUnit, health, MAX_BARRIER, snapshot, unitFrom,
  type Unit, type UnitSnapshot,
} from "../../battle/unit.js";
import { instantClaims, roundEndClaims, setupVictory, timeoutWinner, type VictoryState } from "../../battle/victory.js";

/**
 * 回合制战斗。完全确定：同样的输入永远得到同样的结果。
 *
 * 每轮双方轮流出手（同一方按 1→2→3 号位），奇数轮由 first 先手，偶数轮换另一方。
 * 每次攻击都是一次碰撞：守护改写目标 → 连击分两段 → 被打的人反击 → 屏障挡段、护甲减段
 * → 双方一起扣血 → 吸血 → 移除倒下的人 → 触发“有人倒下”的能力 → 检查能立刻获胜的规则。
 * 轮末再结算场地效果和需要“保持”的规则。
 */

export interface BattleInput {
  teams: [TeamSetup, TeamSetup];
  ruleId: string;
  arenaId: string;
  /** 本手生效的公共效果；没有生效则为 null。 */
  publicEffectId: string | null;
  /** 本手奖池（赌徒酒窖用）。 */
  pot: number;
  /** 第 1 轮先出手的一方（牌桌上是非庄家）；之后每轮轮换。默认 0。 */
  firstSeat?: Seat;
  /** 战役规则 + 魔神牌（实验用）。 */
  campaign?: CampaignOptions;
}

/** 实验：战役规则开关与双方带的魔神牌。 */
export interface CampaignOptions {
  demons: [CharacterDef | null, CharacterDef | null];
  /** 对位倒下后直接打最近的敌人，不花转线回合。 */
  nearest: boolean;
  /** 炼狱业火：第 4 轮起每轮末全场受伤 1、2、3…… */
  hellfire: boolean;
  /** 护甲换成血（护甲 1 → 血 +2）。 */
  armorToHp: boolean;
  /** 魔神从第几轮起可以降临。 */
  descendFrom?: number;
  /** 空位一出现就马上降临（不等下一轮开始）。 */
  immediate?: boolean;
}

/** 回放的一帧：一次出手（或轮初、轮末效果）里发生的事件，以及之后的样子。 */
export interface BattleFrame {
  round: number;
  events: BattleEvent[];
  after: [UnitSnapshot[], UnitSnapshot[]];
}

export type BattleEvent =
  | { round: number; type: "attack"; seat: Seat; pos: number; targetSeat: Seat; targetPos: number; segments: number[] }
  /** 碰撞：被打的人把自己的攻打回攻击者。 */
  | { round: number; type: "recoil"; seat: Seat; pos: number; targetSeat: Seat; targetPos: number; amount: number }
  | { round: number; type: "blocked"; seat: Seat; pos: number }
  | { round: number; type: "damage"; seat: Seat; pos: number; amount: number; hpAfter: number }
  | { round: number; type: "heal"; seat: Seat; pos: number; amount: number }
  | { round: number; type: "switch"; seat: Seat; pos: number; remaining: number }
  | { round: number; type: "death"; seat: Seat; pos: number }
  /** 能力、场地、公共效果在某人身上生效（给画面播放用；round 0 = 开战时）。 */
  | { round: number; type: "trigger"; seat: Seat; pos: number; name: string; text: string }
  | { round: number; type: "note"; text: string };

export interface BattleResult {
  /** null = 平局。 */
  winner: Seat | null;
  reason: "达成规则" | "到时比较" | "平局";
  rounds: number;
  events: BattleEvent[];
  final: [UnitSnapshot[], UnitSnapshot[]];
  /** 开战准备做完、第 1 轮之前的快照，给回放用。 */
  start: [UnitSnapshot[], UnitSnapshot[]];
  /** 每一轮结束后的快照（提前结束的那一轮取结束时）。 */
  timeline: Array<[UnitSnapshot[], UnitSnapshot[]]>;
  /** 逐次出手的回放帧。 */
  frames: BattleFrame[];
  /** 第 1 轮先出手的一方。 */
  first: Seat;
  /** 实验：魔神在第几轮降临（没降临为 0）。 */
  descended: [number, number];
  /** 实验：金山收到的利息。 */
  interest: [number, number];
  /** 实验：第一个倒下的人属于哪一方（没人倒下为 null）。 */
  firstDeathSeat: Seat | null;
  /** 实验：业火烧过几次。 */
  hellfireTicks: number;
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
  private readonly start: [UnitSnapshot[], UnitSnapshot[]];
  private readonly victory: VictoryState;
  private readonly maxRounds: number;
  private round = 0;
  private firstDeathDone: [boolean, boolean] = [false, false];
  private loneTriggered: [boolean, boolean] = [false, false];
  private wingUsed: [boolean, boolean] = [false, false];
  private readonly first: Seat;
  private readonly frames: BattleFrame[] = [];
  private frameMark = 0;
  /** 这一轮不出手的人。 */
  private readonly idle = new Set<Unit>();
  /** 这一轮每人被谁打过（集火回响用）。 */
  private readonly hitThisRound = new Map<Unit, Set<Unit>>();
  private readonly camp: CampaignOptions | null;
  private readonly grave: [Unit[], Unit[]] = [[], []];
  private descended: [number, number] = [0, 0];
  private interest: [number, number] = [0, 0];
  private firstDeathSeat: Seat | null = null;
  private hellfireTicks = 0;
  /** 晨星的决斗：双方互相指向。 */
  private readonly duel = new Map<Unit, Unit>();
  /** 万蝇之王：降临后马上出手。 */
  private hungry: Unit[] = [];
  /** 金山被打中时收多少（实验参数）。 */
  interestPerHit = Number(process.env.INTEREST_HIT ?? 5);
  interestPerAtk = Number(process.env.INTEREST_ATK ?? 5);
  interestCap = Number(process.env.INTEREST_CAP ?? 20);

  constructor(private readonly input: BattleInput) {
    this.env = new Set([input.arenaId, ...(input.publicEffectId ? [input.publicEffectId] : [])]);
    this.first = input.firstSeat ?? 0;
    this.camp = input.campaign ?? null;
    this.bet = [input.teams[0].bet, input.teams[1].bet];
    this.teams = [this.buildTeam(0), this.buildTeam(1)];
    this.setupBattle();
    this.victory = setupVictory(input.ruleId, this.teams, [this.bet[0].revealedPos, this.bet[1].revealedPos]);
    this.maxRounds = this.camp?.hellfire ? 40 : maxRoundsFor(input.ruleId);
    this.start = [this.teams[0].map(snapshot), this.teams[1].map(snapshot)];
  }

  // ───────────────────────── 开战前 ─────────────────────────

  private has(id: string) {
    return this.env.has(id);
  }

  /** 记一条“某人身上有东西生效了”，给画面播放用。 */
  private trig(u: Unit, name: string, text: string) {
    this.events.push({ round: this.round, type: "trigger", seat: u.seat, pos: u.pos, name, text });
  }

  /** 静默书库：第 1 轮所有人物能力失效，开战时能力也不发动。 */
  private abilityOn(u: Unit, name: string): boolean {
    if (!u.def || u.def.name !== name) return false;
    if (this.has("A05") && this.round <= 1) return false;
    return true;
  }

  private buildTeam(seat: Seat): Unit[] {
    const setup = this.input.teams[seat];
    const team = setup.slots.map((s, pos) =>
      s.characterId ? unitFrom(character(s.characterId), seat, pos) : emptyUnit(seat, pos),
    );
    if (this.input.campaign?.armorToHp) {
      for (const u of team) if (u.exists && u.armorBase > 0) { u.hp += 2 * u.armorBase; u.armorBase = 0; }
    }
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
      this.trig(eater, "饕餮", `吞掉${eaten.def!.name}：+${eaten.def!.atk}/+${eaten.def!.hp}`);
      team[setup.eat.eaten] = emptyUnit(seat, setup.eat.eaten);
    }
    return team;
  }

  private setupBattle() {
    const [A, B] = this.teams;
    const all = [...A, ...B].filter((u) => u.exists);
    const startAbilities = !this.has("A05");
    const opp = (u: Unit) => this.teams[other(u.seat)][u.pos];
    if (!startAbilities) this.events.push({ round: 0, type: "note", text: "静默书库：开战时的能力都不发动" });

    // 扒手：同时拿走对位的装备
    if (startAbilities) {
      const before = new Map(all.map((u) => [u, u.equipmentIds.slice()]));
      for (const u of all) {
        const o = opp(u);
        if (u.def?.name === "扒手" && o.exists) {
          u.equipmentIds.push(...before.get(o)!);
          o.equipmentIds = o.equipmentIds.filter((id) => !before.get(o)!.includes(id));
          if (before.get(o)!.length) {
            this.trig(u, "扒手", `夺走「${before.get(o)!.map((id) => equipment(id).name).join("、")}」`);
            this.trig(o, "扒手", "装备被夺走");
          }
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
          const name = u.def!.name;
          switch (name) {
            case "小红帽": {
              const n = foe.betOrRaiseCount;
              if (n) { u.atk += 2 * n; this.trig(u, name, `对手加注 ${n} 次：攻 +${2 * n}`); }
              break;
            }
            case "豪商": {
              const k = Math.min(4, Math.floor(me.invested / 10));
              if (k) { u.atk += k; u.hp += k; this.trig(u, name, `投入 ${me.invested}：+${k}/+${k}`); }
              break;
            }
            case "赎罪券商": {
              const n = Math.min(2, me.opsPaid);
              if (n) { this.addBarrier(u, n, false); this.trig(u, name, `付过 ${me.opsPaid} 次操作费：屏障 +${n}`); }
              break;
            }
            case "冬眠熊":
              if (me.checkCount) { u.hp += 4 * me.checkCount; this.trig(u, name, `过牌 ${me.checkCount} 次：血 +${4 * me.checkCount}`); }
              break;
            case "沉眠巨像":
              if (me.checkCount) { u.atk += 2 * me.checkCount; this.trig(u, name, `过牌 ${me.checkCount} 次：攻 +${2 * me.checkCount}`); }
              break;
            case "孔雀":
              if (me.revealedPos === u.pos) { u.atk += 3; u.hp += 4; this.trig(u, name, "被亮出：+3/+4"); }
              break;
            case "金库守卫":
              if ((me.stack ?? 0) > (foe.stack ?? 0)) { this.addBarrier(u, 1, false); this.trig(u, name, "筹码领先：屏障 +1"); }
              break;
          }
        }
        // 双子：站在 2 号位、两侧都有队友，全队血 +2
        const twin = this.teams[seat][1];
        if (twin.exists && twin.def!.name === "双子" && this.teams[seat][0].exists && this.teams[seat][2].exists) {
          for (const x of this.teams[seat]) if (x.exists) x.hp += 2;
          this.trig(twin, "双子", "两侧都有队友：全队血 +2");
        }
        const healer = this.teams[seat].find((u) => u.exists && u.def!.name === "隐修士");
        if (me.opsPaid === 0 && healer) {
          for (const u of this.teams[seat]) if (u.exists) u.hp += 5;
          this.trig(healer, "隐修士", "没付操作费：全队血 +5");
        }
      }
      // 镜中人：看的是对位此刻的攻和形状
      const copy = all.filter((u) => u.def!.name === "镜中人" && opp(u).exists).map((u) => [u, opp(u).atk, opp(u).shape] as const);
      for (const [u, atk, shape] of copy) {
        u.atk = Math.max(u.atk, atk);
        u.shape = shape;
        this.trig(u, "镜中人", `复制对位：攻 ${u.atk}，${shape === "heavy" ? "重击" : "连击"}`);
      }
    }

    // 场地的开战效果
    for (const team of this.teams) {
      const here = team.filter((u) => u.exists);
      if (here.length === 0) continue;
      if (this.has("A11")) { const lo = minBy(here, (u) => u.hp); lo.atk += 2; lo.hp += 3; this.trig(lo, "陋巷", "血最低：+2/+3"); }
      if (this.has("A12")) { const hi = maxBy(here, (u) => u.atk); hi.atk = Math.max(0, hi.atk - 3); this.trig(hi, "高塔倾覆", "攻最高：攻 -3"); }
      if (this.has("A08")) {
        const b = Math.floor(this.input.pot / 40);
        if (b) for (const u of here) { u.atk += b; this.trig(u, "赌徒酒窖", `攻 +${b}`); }
      }
      if (this.has("A14")) {
        const avg = Math.floor(here.reduce((s, u) => s + u.hp, 0) / here.length);
        for (const u of here) { u.hp = avg; this.trig(u, "天平大厅", `血改为 ${avg}`); }
      }
      if (this.has("A09")) for (const u of here) { this.addBarrier(u, 1, false); this.trig(u, "石柱庭院", "屏障 +1"); }
      if (this.has("P02")) for (const u of here) { u.armorBase += 2; this.trig(u, "铁幕", "护甲 +2"); }
    }
    for (const u of all) { u.startHp = u.hp; u.maxHp = u.hp; }
    // 开场审判是开战后的伤害，不改变开战血量
    if (this.has("P29")) {
      for (const team of this.teams) {
        const here = team.filter((u) => u.exists);
        if (here.length) {
          const u = maxBy(here, (x) => armorOf(x));
          u.hp -= 3;
          this.trig(u, "开场审判", "护甲最高：受到 3 伤害");
        }
      }
    }

    // 缔结、魅惑、沉眠
    for (const u of all) {
      const o = opp(u);
      if (u.def!.name === "沉眠巨像") u.skipRounds = 1;
      if (!startAbilities || !o.exists) continue;
      if (u.def!.name === "牵线人") {
        u.bonded = true;
        o.bonded = true;
        this.trig(u, "牵线人", "与对位缔结：双方本场都不出手");
        this.trig(o, "牵线人", "被缔结：本场不出手");
      }
      if (u.def!.name === "塞壬") { o.charmed = true; this.trig(o, "塞壬", "被魅惑：第一轮打自己人"); }
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
        this.trig(t, "屏障回声", "屏障 +1");
      }
    }
  }

  // ───────────────────────── 战斗 ─────────────────────────

  run(): BattleResult {
    this.pushFrame(); // 开战时的效果
    for (this.round = 1; this.round <= this.maxRounds; this.round++) {
      const decided = this.playRound();
      if (decided) return decided;
      const claims = roundEndClaims(this.victory, this.vteams(), this.round);
      const done = this.decide(claims);
      if (done) return done;
      this.timeline.push([this.teams[0].map(snapshot), this.teams[1].map(snapshot)]);
    }
    this.round = this.maxRounds;
    const w = timeoutWinner(this.victory, this.vteams());
    return this.finish(w, w === null ? "平局" : "到时比较");
  }

  /** 有人达成胜利条件就结束；双方同时达成（例如同归于尽）算平局。 */
  private decide(claims: [boolean, boolean]): BattleResult | null {
    if (!claims[0] && !claims[1]) return null;
    if (claims[0] && claims[1]) return this.finish(null, "平局");
    return this.finish(claims[0] ? 0 : 1, "达成规则");
  }

  /** 判胜用的队伍：被魔神顶掉的倒下者仍算作“已被击倒”。 */
  private vteams(): [Unit[], Unit[]] {
    return [[...this.teams[0], ...this.grave[0]], [...this.teams[1], ...this.grave[1]]];
  }

  private isDemon(u: Unit, name: string) {
    return !!u.def && u.def.name === name && u.flags.has("魔神");
  }

  /** 魔神降临：本方有空位时补到编号最小的空位上。 */
  private descend(seat: Seat) {
    const def = this.camp?.demons[seat];
    if (!def || this.descended[seat]) return;
    const team = this.teams[seat];
    const pos = team.findIndex((u) => !u.alive);
    if (pos < 0) return;
    if (team[pos].exists) this.grave[seat].push(team[pos]);
    const d = unitFrom(def, seat, pos);
    d.flags.add("魔神");
    team[pos] = d;
    this.descended[seat] = this.round;
    this.trig(d, def.name, "魔神降临");
    const foes = this.alive(other(seat));
    if (!foes.length) return;
    if (def.name === "晨星") {
      const champ = maxBy(foes, (x) => x.atk);
      this.duel.set(d, champ);
      this.duel.set(champ, d);
      this.trig(d, def.name, `决斗：向${champ.def!.name}下战书`);
    }
    if (def.name === "深渊之眼") {
      for (const f of foes) if (f.atk > 1) { f.atk--; d.atk++; this.trig(d, def.name, `夺攻：${f.def!.name}攻 -1`); }
    }
    if (def.name === "万蝇之王") this.hungry.push(d);
    if (def.name === "金山") this.interest[seat] = Math.min(this.interestCap, this.interest[seat] + this.interestPerAtk);
    if (def.name === "欲之王") {
      const t = maxBy(foes, (x) => x.hp);
      const mine = d.hp;
      d.hp = t.hp; t.hp = Math.max(1, mine);
      d.maxHp = Math.max(d.maxHp, d.hp); d.startHp = Math.max(d.startHp, d.hp);
      this.trig(d, def.name, `换心：和${t.def!.name}交换血量`);
    }
  }

  private finish(winner: Seat | null, reason: BattleResult["reason"]): BattleResult {
    this.pushFrame();
    if (this.timeline.length < this.round) this.timeline.push([this.teams[0].map(snapshot), this.teams[1].map(snapshot)]);
    return {
      winner, reason, rounds: this.round, events: this.events, start: this.start, timeline: this.timeline,
      frames: this.frames, first: this.first,
      descended: this.descended, interest: this.interest, firstDeathSeat: this.firstDeathSeat, hellfireTicks: this.hellfireTicks,
      final: [this.teams[0].map(snapshot), this.teams[1].map(snapshot)],
    };
  }

  /** 把上一帧之后新发生的事件记成一帧，并附上此刻的快照。 */
  private pushFrame() {
    if (this.frameMark >= this.events.length) return;
    this.frames.push({
      round: this.round,
      events: this.events.slice(this.frameMark),
      after: [this.teams[0].map(snapshot), this.teams[1].map(snapshot)],
    });
    this.frameMark = this.events.length;
  }

  private alive(seat: Seat) {
    return this.teams[seat].filter((u) => u.alive);
  }

  /**
   * 进行一轮：双方轮流出手，同一方按 1→2→3 号位的顺序，每人一次。
   * 奇数轮由 first 先手，偶数轮换另一方先手。每次攻击后立刻结算，并检查能立刻获胜的规则。
   */
  private playRound(): BattleResult | null {
    const r = this.round;

    // 轮初效果
    if (this.has("P06") && (r === 2 || r === 4 || r === 6)) {
      for (const seat of [0, 1] as Seat[]) {
        const al = this.alive(seat);
        if (al.length) { const u = minBy(al, health); this.addBarrier(u, 1); this.trig(u, "庇护潮", "屏障 +1"); }
      }
    }
    if (this.has("P30") && r === 2) {
      for (const u of [...this.alive(0), ...this.alive(1)]) {
        if (u.lostTotal === 0) { this.addBarrier(u, 1); this.trig(u, "迟到的庇护", "屏障 +1"); }
      }
    }

    // 魔神降临
    if (this.camp && r >= (this.camp.descendFrom ?? 2)) for (const seat of [0, 1] as Seat[]) this.descend(seat);

    // 这一轮不出手的人（也不反击）
    this.idle.clear();
    this.hitThisRound.clear();
    for (const seat of [0, 1] as Seat[]) {
      const actors = this.alive(seat);
      const lowest = actors.length ? minBy(actors, (u) => u.hp) : null;
      for (const u of actors) {
        if (u.bonded) this.idle.add(u);
        else if (r <= u.skipRounds) { this.idle.add(u); this.trig(u, "沉眠巨像", "沉睡中，不出手"); }
        else if (this.has("A03") && r === 1) this.idle.add(u);
        else if (this.has("A13") && r === 1 && u !== lowest) this.idle.add(u);
        else if (u.skipNext) { u.skipNext = false; this.idle.add(u); this.trig(u, "沉重后坐", "这一轮不出手"); }
      }
    }
    this.pushFrame();

    // 万蝇之王：降临后马上出手一次
    for (const u of this.hungry.splice(0)) {
      if (!u.alive || !this.alive(other(u.seat)).length) continue;
      u.flags.delete("刚击倒");
      this.trig(u, "万蝇之王", "饿坏了：马上出手");
      this.takeTurn(u);
      this.pushFrame();
      const done = this.decide(instantClaims(this.victory, this.vteams()));
      if (done) return done;
      while (u.alive && u.flags.has("刚击倒") && this.alive(other(u.seat)).length) {
        u.flags.delete("刚击倒");
        this.trig(u, "万蝇之王", "还没吃饱：再出手一次");
        this.takeTurn(u);
        this.pushFrame();
        const again = this.decide(instantClaims(this.victory, this.vteams()));
        if (again) return again;
      }
    }

    const queue: [Unit[], Unit[]] = [this.alive(0), this.alive(1)];
    let side: Seat = r % 2 === 1 ? this.first : other(this.first);
    while (queue[0].length || queue[1].length) {
      if (!queue[side].length) side = other(side);
      const u = queue[side].shift()!;
      side = other(side);
      if (!u.alive || this.idle.has(u)) continue;
      u.flags.delete("刚击倒");
      this.takeTurn(u);
      this.pushFrame();
      const done = this.decide(instantClaims(this.victory, this.vteams()));
      if (done) return done;
      if (this.camp?.immediate && r >= (this.camp.descendFrom ?? 2)) {
        for (const seat of [0, 1] as Seat[]) {
          const had = this.descended[seat];
          this.descend(seat);
          if (!had && this.descended[seat]) {
            const d = this.teams[seat].find((x) => x.flags.has("魔神"))!;
            queue[seat].push(d);
          }
        }
      }
      // 万蝇之王：自己出手击倒敌人后，马上再出手一次
      while (this.isDemon(u, "万蝇之王") && u.alive && u.flags.has("刚击倒") && this.alive(other(u.seat)).length) {
        u.flags.delete("刚击倒");
        this.trig(u, "万蝇之王", "还没吃饱：再出手一次");
        this.takeTurn(u);
        this.pushFrame();
        const again = this.decide(instantClaims(this.victory, this.vteams()));
        if (again) return again;
      }
    }

    // 轮末效果
    if (this.has("P24")) for (const u of this.livingAll()) if (u.regenRounds > 0 && u.hp > 0) { u.regenRounds--; this.heal(u, 2); }
    if (this.camp?.hellfire && r >= 4) {
      this.hellfireTicks++;
      for (const u of this.livingAll()) this.loseHp(u, r - 3);
    }
    this.resolveDeaths(new Map());
    this.pushFrame();
    return null;
  }

  /** 对位已倒下、这一轮还要花时间转线的人。 */
  private switching(u: Unit): boolean {
    if (this.camp?.nearest) return false;
    if (this.teams[other(u.seat)][u.pos].alive) return false;
    if (u.charmed && this.round === 1) return false;
    return (u.switchRemaining ?? this.switchCost(u.pos)) > 0;
  }

  /** 被打时会不会把攻打回去：这一轮不出手、正在转线的人不反击。 */
  private retaliates(t: Unit): boolean {
    return t.alive && t.atk > 0 && !this.idle.has(t) && !this.switching(t);
  }

  /** 一个人的回合：选目标（或花时间转线），然后攻击。 */
  private takeTurn(u: Unit) {
    const r = this.round;
    const seat = u.seat;
    let target: Unit | null = null;
    let opposite = false;
    const o = this.teams[other(seat)][u.pos];
    if (u.charmed && r === 1) {
      const adj = this.teams[seat].filter((x) => x.alive && Math.abs(x.pos - u.pos) === 1);
      if (adj.length) { target = minBy(adj, (x) => x.hp); this.trig(u, "塞壬", "被魅惑：攻击队友"); }
    }
    // 永眠：从不出手
    if (this.isDemon(u, "永眠")) return;
    // 晨星的决斗：双方只打对方
    const rival = this.duel.get(u);
    if (rival && rival.alive) { target = rival; opposite = rival === o; }
    else if (rival) this.duel.delete(u);
    // 焚怒：每次出手打所有敌人（逐个结算，实验近似）
    if (this.isDemon(u, "焚怒")) {
      for (const t of this.alive(other(seat))) {
        if (!u.alive) break;
        if (t.alive) this.strike(u, t, t === o);
      }
      return;
    }
    if (!target) {
      if (o.alive) {
        target = o;
        opposite = true;
      } else {
        if (this.camp?.nearest) {
          const foes = this.alive(other(seat));
          if (!foes.length) return;
          const dist = Math.min(...foes.map((x) => Math.abs(x.pos - u.pos)));
          target = minBy(foes.filter((x) => Math.abs(x.pos - u.pos) === dist), (x) => x.hp);
          for (let k = 0; k < 1; k++) this.strike(u, target, false);
          return;
        }
        if (u.switchRemaining === null) u.switchRemaining = this.switchCost(u.pos);
        if (u.switchRemaining > 0) {
          u.switchRemaining--;
          this.events.push({ round: r, type: "switch", seat, pos: u.pos, remaining: u.switchRemaining });
          return;
        }
        const foes = this.alive(other(seat));
        if (!foes.length) return;
        // 转线后打血最少的
        target = minBy(foes, (x) => x.hp);
      }
    }
    const times = this.has("P13") && r === 3 && u.attacks < 2 ? 2 : 1;
    for (let k = 0; k < times; k++) {
      if (!u.alive || !target.alive) break;
      this.strike(u, target, opposite);
    }
  }

  /** 一次攻击 = 一次碰撞：攻击者打出自己的攻，同时吃下被打那一方的攻。 */
  private strike(a: Unit, target: Unit, opposite: boolean) {
    const r = this.round;
    let t = target;

    // 守护改写目标
    if (t.seat !== a.seat && this.duel.get(a) !== t) {
      const guard = this.teams[t.seat].find(
        (g) => g.alive && g !== t && Math.abs(g.pos - t.pos) === 1 && this.abilityOn(g, "痴情骑士"),
      );
      if (guard) {
        this.trig(guard, "痴情骑士", `守护：替${t.def!.name}挡下`);
        t = guard;
        opposite = false;
      }
    }

    // 集火回响：同一轮被第二个人攻击时，先得一层屏障
    if (t.seat !== a.seat) {
      const by = this.hitThisRound.get(t) ?? this.hitThisRound.set(t, new Set()).get(t)!;
      by.add(a);
      if (this.has("P14") && by.size >= 2 && !t.focusEchoUsed) {
        t.focusEchoUsed = true;
        this.addBarrier(t, 1);
        this.trig(t, "集火回响", "屏障 +1");
      }
    }

    // 算出伤害并拆段
    /** 一次攻击：护甲按段减到 0 为止，但整次攻击只要有一段打中，至少扣 1。 */
    interface Hit { a: Unit; t: Unit; sum: number; landed: boolean; minOne: boolean; segs: number }
    /** 一段伤害：a 是伤害来源，t 是承受者；recoil = 碰撞反伤。 */
    interface Seg { a: Unit; t: Unit; amount: number; hit: Hit; recoil: boolean }
    const segs: Seg[] = [];
    const hitList: Hit[] = [];
    const no = ++a.attacks;
    let d = Math.max(0, a.atk + a.pendingBonus);
    a.pendingBonus = 0;
    if (a.huntTarget === t) { d += 2; a.huntTarget = null; }
    if (this.has("P10") && r === 1) d += 2;
    if (this.has("P16") && opposite) d += 1;
    if (this.has("A02") && opposite) d += 1;
    if (this.has("P18") && r >= 4) d += 1;
    if (this.has("P23") && health(a) < 0.3) d += Math.max(1, Math.floor(d * 0.25));
    // 人物能力的攻击加值（先加，再按下面的翻倍类效果乘）
    const bonus = (name: string, n: number, text: string) => { d += n; this.trig(a, name, text); };
    if (this.abilityOn(a, "大野狼") && this.alive(other(a.seat)).length === 1) bonus("大野狼", 4, "收割：伤害 +4");
    if (t.seat !== a.seat && this.abilityOn(a, "影子") && this.bet[t.seat].revealedPos === t.pos) bonus("影子", 2, "看穿亮牌：伤害 +2");
    if (this.abilityOn(a, "守夜人") && r >= 3) bonus("守夜人", 3, "入夜：伤害 +3");
    if (this.abilityOn(a, "无瑕刺客") && a.hp >= a.maxHp) { d *= 2; this.trig(a, "无瑕刺客", "满血：伤害翻倍"); }
    if (this.abilityOn(a, "清算者") && r === 1 && this.bet[other(a.seat)].betOrRaiseCount > 0) { d *= 2; this.trig(a, "清算者", "对手下过注：首轮伤害翻倍"); }
    if (this.has("P11") && (no === 3 || no === 6)) d *= 2;
    if (this.has("P26") && a.pos === 1) d = Math.round(d * 1.25);
    const parts = a.shape === "multi" ? splitMulti(d) : [d];
    this.events.push({ round: r, type: "attack", seat: a.seat, pos: a.pos, targetSeat: t.seat, targetPos: t.pos, segments: parts });
    const hit: Hit = { a, t, sum: 0, landed: false, minOne: true, segs: 0 };
    hitList.push(hit);
    for (const p of parts) segs.push({ a, t, amount: p, hit, recoil: false });
    if (this.has("P09") && r >= 2) {
      // 深夜霜降：独立的一段 1 点伤害，护甲可以挡掉
      const frost: Hit = { a, t, sum: 0, landed: false, minOne: false, segs: 0 };
      hitList.push(frost);
      segs.push({ a, t, amount: 1, hit: frost, recoil: false });
    }
    // 碰撞：被打的人把自己的攻整段打回来（这一轮不出手、正在转线的人除外）
    let back: Hit | null = null;
    if (this.retaliates(t)) {
      const amt = this.isDemon(t, "永眠") ? t.atk * 2 : t.atk;
      this.events.push({ round: r, type: "recoil", seat: t.seat, pos: t.pos, targetSeat: a.seat, targetPos: a.pos, amount: amt });
      back = { a: t, t: a, sum: 0, landed: false, minOne: true, segs: 0 };
      hitList.push(back);
      segs.push({ a: t, t: a, amount: amt, hit: back, recoil: true });
      if (this.isDemon(t, "焚怒")) {
        for (const x of this.alive(a.seat)) {
          if (x === a) continue;
          const splash: Hit = { a: t, t: x, sum: 0, landed: false, minOne: true, segs: 0 };
          hitList.push(splash);
          segs.push({ a: t, t: x, amount: t.atk, hit: splash, recoil: true });
        }
      }
    }

    // 结算每一段（先记账，再一起扣血）
    const dmg = new Map<Unit, number>();
    const hits = new Map<Unit, number>();
    const hitters = new Map<Unit, Set<Unit>>();
    const armorBreaks = new Map<Unit, number>();
    const add = <K>(m: Map<K, number>, k: K, v: number) => m.set(k, (m.get(k) ?? 0) + v);

    for (const s of segs) {
      const { a: src, t: dst } = s;
      if (dst.barrier > 0) {
        dst.barrier--;
        this.events.push({ round: r, type: "blocked", seat: dst.seat, pos: dst.pos });
        this.onBarrierBroken(dst, src, dmg);
        continue;
      }
      let armor = armorOf(dst);
      if (this.has("P04") && health(dst) > 0.75) armor = Math.floor(armor / 2);
      let real = Math.max(0, s.amount - armor);
      s.hit.landed = true;
      // 噬铁软泥：打中带护甲的敌人，腐蚀掉它 1 点护甲（每人只被腐蚀一次；这一段还按原来的护甲算）
      if (src.seat !== dst.seat && armorOf(dst) > 0 && !dst.flags.has("酸蚀") && this.abilityOn(src, "噬铁软泥")) {
        dst.flags.add("酸蚀");
        if (dst.armorBase > 0) dst.armorBase--;
        else dst.armorEquip--;
        this.trig(src, "噬铁软泥", `腐蚀：${dst.def!.name}护甲 -1`);
      }
      // 所有伤害都是整数：减半向下取整，+25% 四舍五入
      if (this.has("A04") && dst.attacks === 0) real = Math.floor(real / 2);
      if (this.has("A06") && r <= 2) real = Math.min(real, Math.max(1, Math.floor(dst.startHp / 4)));
      if (this.has("P26") && dst.pos === 1) real = Math.round(real * 1.25);
      if (this.has("P27") && dst.pos !== 1 && src.pos === 1 && src.seat !== dst.seat && !dst.sideCoverUsed) { dst.sideCoverUsed = true; real = Math.floor(real / 2); }
      s.hit.sum += real;
      if (real <= 0) continue;
      s.hit.segs++;
      add(dmg, dst, real);
      add(hits, dst, 1);
      (hitters.get(dst) ?? hitters.set(dst, new Set()).get(dst)!).add(src);
      if (this.has("P03") && real >= 6) add(armorBreaks, dst, 1);
      if (this.has("P12") && real >= 8 && !s.recoil) src.skipNext = true;
      if (this.has("A07")) {
        for (const x of this.teams[dst.seat]) if (x.alive && Math.abs(x.pos - dst.pos) === 1) add(dmg, x, 1);
      }
    }

    // 每次攻击（和每次反击）至少扣 1；被屏障整段挡掉的不算打中
    for (const h of hitList) {
      if (!h.landed || !h.minOne || h.sum >= 1) continue;
      const top = 1 - h.sum;
      if (h.sum === 0) {
        h.segs = 1;
        add(hits, h.t, 1);
        (hitters.get(h.t) ?? hitters.set(h.t, new Set()).get(h.t)!).add(h.a);
      }
      add(dmg, h.t, top);
    }

    // 碰撞双方同时扣血
    for (const [u, v] of dmg) this.loseHp(u, v);

    // 深渊之眼：打中敌人（反击也算）抢走它 1 点攻
    const steal = (thief: Unit, victim: Unit) => {
      if (victim.atk > 1) { victim.atk--; thief.atk++; this.trig(thief, "深渊之眼", `夺攻：${victim.def!.name}攻 -1`); }
    };
    if (hit.segs > 0 && this.isDemon(a, "深渊之眼旧")) steal(a, t);
    if (back && back.segs > 0 && this.isDemon(t, "深渊之眼旧")) steal(t, a);
    // 金山：每打中一段收 5 筹码，每手最多 30
    if (hit.segs > 0 && this.isDemon(a, "金山")) this.interest[a.seat] = Math.min(this.interestCap, this.interest[a.seat] + this.interestPerAtk);
    if (back && back.segs > 0 && this.isDemon(t, "金山")) this.interest[t.seat] = Math.min(this.interestCap, this.interest[t.seat] + this.interestPerAtk);
    // 金山：被敌人打中也收（碰她一下都要钱）
    if (hit.segs > 0 && this.isDemon(t, "金山")) this.interest[t.seat] = Math.min(this.interestCap, this.interest[t.seat] + this.interestPerHit);

    // 吸血：自己主动攻击每打中一段回 1（反击不算）
    const bites = hit.segs;
    if (bites > 0 && a.hp > 0 && this.abilityOn(a, "放血师")) {
      let heal = bites;
      if (this.has("P19")) heal -= 1;
      if (this.has("P18") && r >= 4) heal -= 1;
      if (heal > 0) {
        if (a.hp < a.maxHp) this.trig(a, "放血师", `吸血 +${heal}`);
        this.heal(a, heal);
      }
    }
    // 狂战士、裂甲
    for (const [u, n] of hits) {
      if (u.hp > 0 && this.abilityOn(u, "狂战士")) { u.atk += n; this.trig(u, "狂战士", `攻 +${n}`); }
    }
    for (const [u, n] of armorBreaks) u.armorBase = Math.max(0, u.armorBase - n);
    // 交际花逢场作戏：打中她的敌人（反击也算），下一次攻击 -2；每个敌人只算一次，这一下把她打倒也照样算
    for (const [u, srcs] of hitters) {
      if (!this.abilityOn(u, "交际花")) continue;
      for (const s of srcs) {
        if (s.seat === u.seat || s.flags.has("逢场作戏")) continue;
        s.flags.add("逢场作戏");
        s.pendingBonus -= 2;
        this.trig(u, "交际花", `逢场作戏：${s.def!.name}下一次攻击 -2`);
      }
    }

    // 攻击带来的自损
    if (this.has("P22") && (no === 2 || no === 4 || no === 6)) { this.loseHp(a, 2); a.pendingBonus += 3; }

    // 移除倒下的人，并处理“有人倒下”
    this.resolveDeaths(hitters);
  }

  private switchCost(pos: number): number {
    if (this.has("A01")) return pos === 0 ? 2 : pos === 2 ? 0 : 1;
    return 1;
  }

  private livingAll() {
    return [...this.teams[0], ...this.teams[1]].filter((u) => u.alive && u.hp > 0);
  }

  private loseHp(u: Unit, v: number) {
    if (v <= 0 || !u.alive) return;
    u.hp = u.hp - v;
    u.lostTotal += v;
    this.events.push({ round: this.round, type: "damage", seat: u.seat, pos: u.pos, amount: v, hpAfter: u.hp });
    if (this.has("P21") && u.hp > 0) {
      u.bloodSpringAcc += v;
      while (u.bloodSpringAcc >= 5) { u.bloodSpringAcc -= 5; this.heal(u, 2); }
    }
  }

  private heal(u: Unit, v: number) {
    if (v <= 0 || u.hp <= 0) return;
    const room = u.maxHp - u.hp;
    const real = Math.min(room, v);
    if (real > 0) {
      u.hp = u.hp + real;
      this.events.push({ round: this.round, type: "heal", seat: u.seat, pos: u.pos, amount: real });
    }
    if (this.has("P20") && v - real > 0 && u.barrier < 1) this.addBarrier(u, 1);
    if (this.has("P25") && real > 0) {
      u.healAcc += real;
      while (u.healAcc >= 4) {
        u.healAcc -= 4;
        const o = this.teams[other(u.seat)][u.pos];
        if (o.alive) this.loseHp(o, 2);
      }
    }
  }

  private onBarrierBroken(t: Unit, attacker: Unit, dmg: Map<Unit, number>) {
    // 攻城锤手：第一次打破敌人的屏障，攻 +2
    if (attacker.seat !== t.seat && !attacker.flags.has("破阵") && this.abilityOn(attacker, "攻城锤手")) {
      attacker.flags.add("破阵");
      attacker.atk += 2;
      this.trig(attacker, "攻城锤手", "破盾：攻 +2");
    }
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
    if (this.has("P31") && r >= 3) {
      for (const u of newlyDead) {
        const o = this.teams[other(u.seat)][u.pos];
        if (o.alive) this.loseHp(o, 3);
      }
      const extra = [...this.teams[0], ...this.teams[1]].filter((u) => u.alive && u.hp <= 0);
      for (const u of extra) { u.alive = false; u.deathRound = r; }
      newlyDead = [...newlyDead, ...extra];
    }
    for (const u of newlyDead) this.events.push({ round: r, type: "death", seat: u.seat, pos: u.pos });
    if (newlyDead.length && this.firstDeathSeat === null) this.firstDeathSeat = newlyDead[0].seat;
    for (const v of newlyDead) for (const k of hitters.get(v) ?? []) if (k.seat !== v.seat) k.flags.add("刚击倒");

    if (newlyDead.length) {
      for (const u of this.livingAll()) {
        if (this.abilityOn(u, "食腐鸦")) {
          const n = newlyDead.length;
          u.atk += n; u.hp += 3 * n; u.maxHp += 3 * n;
          this.trig(u, "食腐鸦", `+${n}/+${3 * n}`);
        }
      }
      for (const v of newlyDead) {
        for (const k of hitters.get(v) ?? []) {
          if (k.alive && k.seat !== v.seat && this.abilityOn(k, "收藏家")) {
            k.atk += 2 + v.eqAtk; k.hp += v.eqHp; k.maxHp += v.eqHp;
            this.trig(k, "收藏家", `击倒${v.def!.name}：攻 +${2 + v.eqAtk}${v.eqHp ? `，血 +${v.eqHp}` : ""}`);
          }
        }
      }
      for (const seat of [0, 1] as Seat[]) {
        if (this.firstDeathDone[seat] || !newlyDead.some((u) => u.seat === seat)) continue;
        this.firstDeathDone[seat] = true;
        for (const u of this.alive(seat)) {
          if (this.has("P15")) { u.pendingBonus += 2; this.trig(u, "重整", "下一次攻击 +2"); }
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
          this.trig(al[0], "孤身余粮", "屏障 +1，接下来 2 轮回血");
        }
      }
    }
    if (this.has("A10")) {
      for (const u of this.livingAll()) {
        if (!u.halfHealthTriggered && health(u) <= 0.5) { u.halfHealthTriggered = true; this.addBarrier(u, 1); this.trig(u, "渗血祭台", "屏障 +1"); }
      }
    }
    if (this.has("P17")) {
      for (const [t, set] of hitters) {
        if (!t.alive || health(t) > 0.25) continue;
        for (const a of set) if (!a.huntUsed && a.seat !== t.seat) { a.huntUsed = true; a.huntTarget = t; }
      }
    }
  }
}

/** 连击：伤害拆成两段整数，奇数时后一段多 1（屏障先挡掉小的那段）；0 的那段不算。 */
export function splitMulti(d: number): number[] {
  const first = Math.floor(d / 2);
  return first > 0 ? [first, d - first] : [d];
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
    case "V21": case "V22": case "V23": case "V24": return 3;
    case "V25": case "V26": case "V27": return 4;
    default: return 8;
  }
}
