import { runBattle } from "../battle/engine.js";
import { CHARACTERS } from "../content/characters.js";
import { ARENAS, arena, publicEffect, rule } from "../content/tables.js";
import { HeuristicAgent, playTable, RandomAgent, type Agent, type Style } from "../ai/agents.js";
import { Table } from "../game/table.js";
import { Rng } from "../rng.js";
import { STAGES } from "../campaign/stages.js";
import { levelOpening, levelStats, levelTables, VARIANTS } from "./campaign.js";
import { randomBattle } from "./sampler.js";

/**
 * 模拟器命令行：
 *   npm run sim -- roster [场数]        人物总胜率与各自的最强 / 最弱情境
 *   npm run sim -- opening [开局数] [每个开局的场数]   开局胜率分布（验收标准：绝大多数落在 30%–80%）
 *   npm run sim -- tables [桌数] [对手A] [对手B]      整张牌桌对局统计（对手：random / cautious / aggressive / bluff）
 *   npm run sim -- level <关卡 0–7 | all> [场数]      战役：战斗统计（转线 / 打最近、有无魔神）+ 整桌手数
 */

const pct = (x: number) => `${(x * 100).toFixed(1)}%`;
const signed = (x: number) => `${x >= 0 ? "+" : ""}${(x * 100).toFixed(0)}`;

function roster(n: number) {
  const rng = new Rng(20260925);
  const total = new Map<string, [number, number]>();
  const ctx = new Map<string, [number, number]>(); // `${id}|${kind}:${key}`
  const base = new Map<string, [number, number]>();
  const bump = (m: Map<string, [number, number]>, k: string, s: number) => {
    const v = m.get(k) ?? [0, 0];
    v[0]++; v[1] += s;
    m.set(k, v);
  };
  let draws = 0;
  for (let i = 0; i < n; i++) {
    const { input, ids } = randomBattle(rng);
    const r = runBattle(input);
    if (r.winner === null) draws++;
    for (const seat of [0, 1] as const) {
      const s = r.winner === seat ? 1 : r.winner === null ? 0.5 : 0;
      const keys = [`规则:${rule(input.ruleId).name}`, `场地:${arena(input.arenaId).name}`,
        `公共效果:${input.publicEffectId ? publicEffect(input.publicEffectId).name : "无"}`];
      for (const k of keys) bump(base, k, s);
      for (const id of ids[seat]) {
        bump(total, id, s);
        for (const k of keys) bump(ctx, `${id}|${k}`, s);
      }
    }
  }
  console.log(`共 ${n} 场，平局 ${pct(draws / n)}\n`);
  const rows = CHARACTERS.map((c) => {
    const [cnt, sum] = total.get(c.id) ?? [1, 0];
    const lifts: Array<[number, string]> = [];
    for (const [k, [m, s]] of ctx) {
      const [id, key] = k.split("|");
      if (id !== c.id || m < 150) continue;
      const [bm, bs] = base.get(key)!;
      lifts.push([s / m - bs / bm, key]);
    }
    lifts.sort((a, b) => a[0] - b[0]);
    return { c, wr: sum / cnt, lo: lifts[0], hi: lifts[lifts.length - 1] };
  }).sort((a, b) => b.wr - a.wr);
  for (const { c, wr, lo, hi } of rows) {
    const flag = wr < 0.45 || wr > 0.55 ? " <<" : "";
    console.log(
      `${c.name.padEnd(5, "　")} ${c.sin} ${`${c.atk}/${c.hp}`.padEnd(5)} 总胜率 ${pct(wr)}${flag}` +
      `   最弱情境 ${lo ? `${signed(lo[0])}（${lo[1]}）` : "-"}   最强情境 ${hi ? `${signed(hi[0])}（${hi[1]}）` : "-"}`,
    );
  }
}

function opening(teams: number, per: number) {
  const rng = new Rng(7);
  const ids = CHARACTERS.map((c) => c.id);
  const wrs: number[] = [];
  for (let t = 0; t < teams; t++) {
    const mine = rng.sample(ids, 3);
    const arenaId = rng.pick(ARENAS).id;
    let score = 0;
    for (let i = 0; i < per; i++) {
      const r = runBattle(randomBattle(rng, mine, arenaId).input);
      score += r.winner === 0 ? 1 : r.winner === null ? 0.5 : 0;
    }
    wrs.push(score / per);
  }
  wrs.sort((a, b) => a - b);
  const q = (x: number) => wrs[Math.floor(x * (wrs.length - 1))];
  const band = wrs.filter((x) => x >= 0.3 && x <= 0.8).length / wrs.length;
  console.log(`开局 ${teams} 个，每个 ${per} 场`);
  console.log(`最差一成 ${pct(q(0.1))} · 中位 ${pct(q(0.5))} · 最好一成 ${pct(q(0.9))}`);
  console.log(`落在 30%–80%：${pct(band)}（验收标准：绝大多数）· 低于 20%：${pct(wrs.filter((x) => x < 0.2).length / wrs.length)}`);
}

function makeAgent(kind: string, seed: number): Agent {
  if (kind === "random") return new RandomAgent(seed);
  return new HeuristicAgent(kind as Style, seed);
}

function tables(n: number, a: string, b: string) {
  let hands = 0, folds = 0, battles = 0;
  const wins = [0, 0];
  let leaderWins = 0, leaderCases = 0;
  for (let seed = 1; seed <= n; seed++) {
    const t = new Table({ seed });
    playTable(t, [makeAgent(a, seed * 2), makeAgent(b, seed * 2 + 1)]);
    hands += t.handNo;
    folds += t.log.filter((e) => e.type === "fold").length;
    battles += t.log.filter((e) => e.type === "battle").length;
    if (t.winner !== null) wins[t.winner]++;
    const settles = t.log.filter((e) => e.type === "settle");
    const third = settles[2];
    if (third && third.type === "settle" && t.winner !== null && third.stacks[0] !== third.stacks[1]) {
      leaderCases++;
      if ((third.stacks[0] > third.stacks[1] ? 0 : 1) === t.winner) leaderWins++;
    }
  }
  console.log(`${n} 张牌桌：${a} 对 ${b}`);
  console.log(`胜场 ${wins[0]} : ${wins[1]} · 平均每桌 ${(hands / n).toFixed(1)} 手 · 弃牌结束的手 ${pct(folds / Math.max(1, folds + battles))}`);
  if (leaderCases) console.log(`第 3 手后筹码领先的一方最终赢下牌桌：${pct(leaderWins / leaderCases)}（${leaderCases} 桌）`);
}

function level(which: string, n: number) {
  const levels = which === "all" ? STAGES.map((s) => s.no) : [Number(which)];
  for (const lv of levels) {
    if (!STAGES[lv]) throw new Error(`没有第 ${which} 关（0 = 序章，1–7 = 七姐妹）`);
    console.log(`\n── ${lv === 0 ? "序章" : `第 ${lv} 关`} · ${n} 场 ──`);
    for (const v of VARIANTS) {
      if (lv === 0 && v.demons) continue; // 序章没有魔神
      const s = levelStats(lv, v, n);
      const wrs = levelOpening(lv, v, 150, 60);
      const band = wrs.filter((x) => x >= 0.3 && x <= 0.8).length / wrs.length;
      console.log(
        `${v.name.padEnd(9, "　")} 平均 ${s.avgRounds.toFixed(2)} 轮 · 业火烧到 ${pct(s.hellfire / n)} · 平局 ${pct(s.draws / n)}` +
        ` · 先击倒胜率 ${pct(s.firstKillWins / Math.max(1, s.firstKillCases))}` +
        (v.demons ? ` · 魔神降临 ${pct(s.demon / n)} · 降临局翻盘 ${pct(s.comeback / Math.max(1, s.comebackCases))}` : "") +
        ` · 开局胜率落在 30%–80% ${pct(band)}`,
      );
    }
    const t = levelTables(lv, Math.max(20, Math.round(n / 200)));
    console.log(
      `整桌（${t.tables} 桌，你用“谨慎”）：你赢 ${pct(t.won / t.tables)} · 平均 ${t.avgHands.toFixed(1)} 手` +
      ` · 弃牌结束的手 ${pct(t.foldShare)}` + (t.interest ? ` · 金山利息共 ${t.interest}` : ""),
    );
  }
}

const [cmd = "roster", ...args] = process.argv.slice(2);
const num = (i: number, d: number) => (args[i] ? Number(args[i]) : d);
switch (cmd) {
  case "roster": roster(num(0, 60000)); break;
  case "opening": opening(num(0, 400), num(1, 120)); break;
  case "tables": tables(num(0, 100), args[1] ?? "cautious", args[2] ?? "aggressive"); break;
  case "level": level(args[0] ?? "all", num(1, 20000)); break;
  default:
    console.log("用法：roster [场数] | opening [开局数] [每个开局场数] | tables [桌数] [对手A] [对手B] | level <关卡|all> [场数]");
}
