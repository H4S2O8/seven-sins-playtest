import { CHARACTERS } from "../../content/characters.js";
import { Rng } from "../../rng.js";
import type { BetContext, CharacterDef, Seat, TeamSetup } from "../../types.js";
import { runBattle, type BattleInput, type BattleResult, type CampaignOptions } from "./engine.js";

/**
 * 魔神牌实验：战役规则（无装备、无公共效果、护甲换血、打最近、业火）下，
 * 比较带与不带魔神的同一场战斗。
 *   npx tsx src/sim/lab/demons.ts [场数] [参数覆盖 JSON]
 * 参数覆盖例：'{"晨星":[5,10]}' 改攻 / 血。
 */

type Stats = Record<string, [number, number]>;

const demon = (name: string, sin: CharacterDef["sin"], atk: number, hp: number, shape: CharacterDef["shape"], ability: string): CharacterDef => ({
  id: `D-${name}`, name, sin, atk, hp, shape, armor: 0, barrier: 0, ability, tag: "魔神", stage: 1,
});

export function demons(over: Stats = {}): CharacterDef[] {
  const s = (n: string, a: number, h: number): [number, number] => over[n] ?? [a, h];
  return [
    demon("晨星", "傲慢", ...s("晨星", 5, 10), "heavy", "决斗"),
    demon("深渊之眼", "嫉妒", ...s("深渊之眼", 2, 12), "heavy", "夺攻"),
    demon("焚怒", "愤怒", ...s("焚怒", 3, 14), "heavy", "横扫"),
    demon("永眠", "怠惰", ...s("永眠", 3, 14), "heavy", "只反击"),
    demon("金山", "贪婪", ...s("金山", 4, 12), "heavy", "利息"),
    demon("万蝇之王", "暴食", ...s("万蝇之王", 4, 8), "heavy", "还没吃饱"),
    demon("欲之王", "色欲", ...s("欲之王", 5, 3), "heavy", "换心"),
  ];
}

/** 战役牌池：扒手移出。 */
const ROSTER = CHARACTERS.filter((c) => c.id !== "EN3").map((c) => c.id);

/** 第 1–7 关的专属规则与主场。 */
const STAGES: Array<{ rule: string; arena: string }> = [
  { rule: "V12", arena: "none" },
  { rule: "V08", arena: "none" },
  { rule: "V03", arena: "none" },
  { rule: "V07", arena: "none" },
  { rule: "V09", arena: "none" },
  { rule: "V01", arena: "A07" },
  { rule: "*", arena: "A04" },
];

function campaignBet(rng: Rng): BetContext {
  const raises = rng.pick([0, 0, 1, 1, 2, 3]);
  const checks = raises === 0 ? rng.pick([1, 2, 2]) : rng.pick([0, 0, 1]);
  return {
    invested: 5 + raises * 15 + rng.pick([0, 10, 20]),
    betOrRaiseCount: raises,
    checkCount: checks,
    // 战役版赎罪券商按加注次数给屏障、隐修士看“没下注或加注过”：都读这个数
    opsPaid: raises,
    revealedPos: rng.int(3),
    stack: rng.pick([40, 70, 100, 130, 160]),
  };
}

function campaignTeam(rng: Rng): TeamSetup {
  const chars = rng.sample(ROSTER, 3);
  const bet = campaignBet(rng);
  const slots = chars.map((c) => ({ characterId: c, equipmentId: null as string | null }));
  let eat: TeamSetup["eat"] = null;
  const g = chars.indexOf("GL2");
  if (g >= 0 && rng.next() < 0.5) {
    const others = [0, 1, 2].filter((i) => i !== g);
    const pw = (i: number) => { const c = CHARACTERS.find((x) => x.id === chars[i])!; return c.atk * c.hp; };
    const eaten = others.reduce((a, b) => (pw(a) <= pw(b) ? a : b));
    eat = { eater: g, eaten };
    if (bet.revealedPos === eaten) bet.revealedPos = g;
  }
  return { slots, eat, bet };
}

function campaignInput(rng: Rng, stage: number): BattleInput {
  const a = campaignTeam(rng);
  const b = campaignTeam(rng);
  const st = STAGES[stage - 1];
  const rule = st.rule === "*" ? rng.pick(["V12", "V08", "V03", "V07", "V09", "V01"]) : st.rule;
  return {
    teams: [a, b], ruleId: rule, arenaId: st.arena, publicEffectId: null,
    pot: a.bet.invested + b.bet.invested, firstSeat: rng.int(2) as Seat,
  };
}

const camp = (d0: CharacterDef | null, d1: CharacterDef | null, descendFrom = Number(process.env.DESCEND_FROM ?? 2)): CampaignOptions =>
  ({ demons: [d0, d1], nearest: true, hellfire: true, armorToHp: true, descendFrom, immediate: process.env.IMMEDIATE !== "0" });

/** 1 号座这一手的净筹码：赢拿走奖池，平局退回，外加利息。 */
const chips = (r: BattleResult, x: BattleInput) => {
  const mine = x.teams[0].bet.invested;
  const base = r.winner === 0 ? x.pot - mine : r.winner === null ? 0 : -mine;
  return base + r.interest[0] - r.interest[1];
};
const score = (r: BattleResult, seat: Seat) => (r.winner === seat ? 1 : r.winner === null ? 0.5 : 0);
const pct = (x: number) => `${(x * 100).toFixed(1)}%`;
const pp = (x: number) => `${x >= 0 ? "+" : ""}${(x * 100).toFixed(1)}`;

class Acc {
  n = 0; win = 0; rounds = 0; fire = 0; draws = 0;
  fdN = 0; fdWin = 0; // 先倒人的一方最终赢（comeback）
  add(r: BattleResult, seat: Seat) {
    this.n++; this.win += score(r, seat); this.rounds += r.rounds; if (r.hellfireTicks > 0) this.fire++;
    if (r.winner === null) this.draws++;
    if (r.firstDeathSeat !== null) { this.fdN++; this.fdWin += score(r, r.firstDeathSeat); }
  }
  get wr() { return this.win / this.n; }
  line() {
    return `胜率 ${pct(this.wr)} · 平均 ${(this.rounds / this.n).toFixed(2)} 轮 · 业火烧起来 ${pct(this.fire / this.n)} · 平局 ${pct(this.draws / this.n)} · 先倒人一方翻盘 ${pct(this.fdWin / Math.max(1, this.fdN))}`;
  }
}

function run(n: number, over: Stats) {
  const DS = demons(over);
  const rng = new Rng(20260926);
  const inputs: Array<{ input: BattleInput; stage: number }> = [];
  for (let i = 0; i < n; i++) { const stage = 1 + rng.int(7); inputs.push({ input: campaignInput(rng, stage), stage }); }
  const withCamp = (x: BattleInput, c: CampaignOptions): BattleInput => ({ ...x, campaign: c });

  console.log(`\n== 基线：双方都没有魔神（${n} 场，第 1–7 关均匀混合）==`);
  const base = new Acc();
  const baseRes = inputs.map(({ input }) => runBattle(withCamp(input, camp(null, null))));
  baseRes.forEach((r) => base.add(r, 0));
  console.log(base.line());

  console.log(`\n== 只有 1 号座带魔神（第 1 关的情形），和同一场不带魔神比 ==`);
  console.log("魔神       攻/血   降临率  平均降临轮  胜率提升  降临后本方胜率  平均轮数  业火  先倒人一方翻盘");
  for (const d of DS) {
    const acc = new Acc();
    let desc = 0, descRound = 0, descWin = 0, interest = 0, lostWithInterest = 0, potSum = 0, intN = 0, ev = 0;
    inputs.forEach(({ input }, i) => {
      const r = runBattle(withCamp(input, camp(d, null)));
      ev += chips(r, input) - chips(baseRes[i], input);
      acc.add(r, 0);
      if (r.descended[0]) {
        desc++; descRound += r.descended[0]; descWin += score(r, 0);
        if (d.name === "金山") { interest += r.interest[0]; potSum += input.pot; intN++; if (r.winner === 1 && r.interest[0] > 0) lostWithInterest++; }
      }
      void i;
    });
    console.log(
      `${d.name.padEnd(5, "　")} ${`${d.atk}/${d.hp}`.padEnd(6)} ${pct(desc / n).padStart(6)}  ${(descRound / Math.max(1, desc)).toFixed(2).padStart(6)}    ${pp(acc.wr - base.wr).padStart(6)}   ${pct(descWin / Math.max(1, desc)).padStart(7)}      ${(acc.rounds / n).toFixed(2)}   ${pct(acc.fire / n)}   ${pct(acc.fdWin / Math.max(1, acc.fdN))}`,
    );
    console.log(`      筹码期望提升（每场，含利息）：${(ev / n).toFixed(2)}`);
    if (d.name === "金山" && intN) {
      console.log(`      金山降临的战斗：平均收利息 ${(interest / intN).toFixed(1)}，平均奖池 ${(potSum / intN).toFixed(1)}；本方战斗输了但仍收到利息 ${pct(lostWithInterest / intN)}`);
    }
  }

  console.log(`\n== 双方都带魔神（第 2 关起的情形）：行 = 1 号座的魔神，数字 = 行的胜率 ==`);
  const names = DS.map((d) => d.name);
  console.log("            " + names.map((x) => x.slice(0, 2).padEnd(5, "　")).join(""));
  const avg: number[] = [];
  const both = new Acc();
  for (const a of DS) {
    let row = "", sum = 0;
    for (const b of DS) {
      const acc = new Acc();
      const m = Math.min(n, 4000);
      for (let i = 0; i < m; i++) acc.add(runBattle(withCamp(inputs[i].input, camp(a, b))), 0);
      for (let i = 0; i < m; i++) both.add(runBattle(withCamp(inputs[i].input, camp(a, b))), 0);
      row += pct(acc.wr).padEnd(7);
      sum += acc.wr;
    }
    avg.push(sum / DS.length);
    console.log(`${a.name.padEnd(5, "　")}  ${row}  平均 ${pct(sum / DS.length)}`);
  }
  console.log(`双方都带魔神时整体：${both.line()}`);

  console.log(`\n== 各关单独看（只有 1 号座带魔神，胜率提升）==`);
  console.log("关  " + names.map((x) => x.slice(0, 2).padEnd(6, "　")).join(""));
  for (let st = 1; st <= 7; st++) {
    const idx = inputs.map((x, i) => [x, i] as const).filter(([x]) => x.stage === st);
    let row = "";
    for (const d of DS) {
      let lift = 0;
      for (const [{ input }, i] of idx) lift += score(runBattle(withCamp(input, camp(d, null))), 0) - score(baseRes[i], 0);
      row += pp(lift / idx.length).padEnd(8);
    }
    console.log(`${st}   ${row}`);
  }
}

export { campaignInput, camp, score, pct, pp, Acc, STAGES };

if (process.argv[1]?.endsWith("demons.ts")) {
  const [nArg, overArg] = process.argv.slice(2);
  run(nArg ? Number(nArg) : 20000, overArg ? JSON.parse(overArg) : {});
}
