import { HeuristicAgent, RandomAgent, playTable } from "../ai/agents.js";
import { Table } from "../game/table.js";

const N = 1000;
const run = (name: string, make: (seed: number) => [any, any]) => {
  let wins = 0, draws = 0, hands = 0, rerolls = 0, targetChanges = 0;
  for (let i = 0; i < N; i++) {
    const t = new Table({ seed: 9000 + i, buyIn: 100 });
    const agents = make(i);
    const before = t.log.length;
    playTable(t, agents, 80, 50000);
    if (t.winner === 0) wins++; else if (t.winner === null) draws++;
    hands += t.handNo;
    rerolls += t.log.slice(before).filter((e: any) => e.type === "traditionalDraft" && e.reroll).length;
    targetChanges += t.log.slice(before).filter((e: any) => e.type === "traditionalPlaced").length;
  }
  console.log(JSON.stringify({ name, games: N, seat0Wins: wins, seat1Wins: N - wins - draws, draws, seat0WinRate: wins / N, averageHands: hands / N, rerollEvents: rerolls, placements: targetChanges }));
};

run("谨慎 vs 激进", (i) => [new HeuristicAgent("cautious", 100 + i, 4), new HeuristicAgent("aggressive", 200 + i, 4)]);
run("随机 vs 爱诈唬", (i) => [new RandomAgent(300 + i), new HeuristicAgent("bluff", 400 + i, 4)]);
