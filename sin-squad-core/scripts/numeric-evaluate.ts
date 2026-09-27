import { mkdirSync, writeFileSync } from 'node:fs';
import { NumericTable } from '../src/numeric/table.js';
import { NumericAgent, type NumericStyle } from '../src/numeric/ai.js';
const styles: NumericStyle[] = ['cautious','aggressive','bluff'];
const rows:any[]=[];
const start=Date.now();
for(let i=0;i<1400;i++) {
  const control=i>=1000, seed=700001+i;
  const t=new NumericTable({seed});
  const pair:NumericStyle[]=[styles[i%3],styles[Math.floor(i/3)%3]];
  const agents=pair.map((s,p)=>new NumericAgent(s,seed^(p+1)*17011));
  const baselineSeat=control?i%2:-1;
  const actions:Record<string,number>={}, states:Record<string,number>={};
  let n=0;
  while(!t.observe(0).result && n++<300) {
    const s=t.observe(0).toAct[0] as 0|1;
    const a=s===baselineSeat?t.baselineAction(s):agents[s].act(t.observe(s));
    if(!a) throw Error(`No action ${seed} ${t.phase}`);
    actions[a.type]=(actions[a.type]??0)+1;
    if(s!==baselineSeat) states[agents[s].state]=(states[agents[s].state]??0)+1;
    t.apply(s,a);
    if(t.pot+t.players[0].stack+t.players[1].stack!==200) throw Error(`Conservation ${seed}`);
  }
  const o=t.observe(0),r=o.result;
  if(!r) throw Error(`Unfinished ${seed}`);
  const raw=t.players.map(p=>p.numbers.reduce((a,b)=>a+b,0));
  rows.push({seed,control,pair,baselineSeat,winner:r.winner,showdown:!!r.powers,round:o.round,actions,states,raw,stacks:o.stacks,pot:r.pot,
    teams:t.players.map(p=>p.slots),tiers:t.players.map(p=>p.numbers.map(n=>n<=4?0:n>=8?2:1)),
    activeEffects:o.effects.filter(e=>e.status==='active').length,trace:r.trace});
  if((i+1)%100===0) console.log(`${i+1}/1400 ${(Date.now()-start)/1000}s`);
}
const main=rows.filter(r=>!r.control), controls=rows.filter(r=>r.control);
const sum=(rs:any[],key:string)=>rs.reduce((o,r)=>{for(const [k,v] of Object.entries(r[key]))o[k]=(o[k]??0)+(v as number);return o;},{} as Record<string,number>);
const sd=main.filter(r=>r.showdown), decisive=sd.filter(r=>r.winner!==null&&r.raw[0]!==r.raw[1]);
// Held-out naive Bayes: equipment likelihood times public tier-composition prior.
const counts=Array.from({length:3},()=>({total:0,gear:{} as Record<string,number>}));
for(const r of main.slice(0,700)) for(const team of r.teams) for(const x of team) {
  const tier=x.number<=4?0:x.number>=8?2:1, c=counts[tier];c.total++;const id=x.equipment?.id??'none';c.gear[id]=(c.gear[id]??0)+1;
}
let seen=0,priorHit=0,gearHit=0,equipped=0,eqPriorHit=0,eqHit=0;
for(const r of main.slice(700)) r.teams.forEach((team:any[],seat:number)=>team.forEach(x=>{
  const prior=[0,1,2].map(t=>r.tiers[seat].filter((v:number)=>v===t).length/3);
  const id=x.equipment?.id??'none',tier=x.number<=4?0:x.number>=8?2:1;
  const post=prior.map((p,t)=>p*((counts[t].gear[id]??0)+1)/(counts[t].total+25));
  const pick=(a:number[])=>a.indexOf(Math.max(...a));
  seen++;priorHit+=Number(pick(prior)===tier);gearHit+=Number(pick(post)===tier);
  if(x.equipment){equipped++;eqPriorHit+=Number(pick(prior)===tier);eqHit+=Number(pick(post)===tier);}
}));
const summary={definition:'1000 independent complete hands AI vs AI; additional 400 vs old baseline; fresh 100 chips each hand; fixed seeds; production six-sample policy; not human fun measurement',elapsedSeconds:(Date.now()-start)/1000,
  main:{hands:main.length,showdowns:sd.length,folds:1000-sd.length,ties:main.filter(r=>r.winner===null).length,meanRounds:main.reduce((a,r)=>a+r.round,0)/1000,meanPot:main.reduce((a,r)=>a+r.pot,0)/1000,actions:sum(main,'actions'),states:sum(main,'states'),rawHigherWins:decisive.filter(r=>r.raw[r.winner]>r.raw[1-r.winner]).length,rawUnequalDecisiveShowdowns:decisive.length,meanEquippedSlots:main.reduce((a,r)=>a+r.teams.flat().filter((x:any)=>x.equipment).length,0)/2000},
  control:{hands:400,newAIWins:controls.filter(r=>r.winner!==null&&r.winner!==r.baselineSeat).length,ties:controls.filter(r=>r.winner===null).length,newAINetChips:controls.reduce((a,r)=>a+r.stacks[1-r.baselineSeat]-100,0)},
  inference:{trainHands:700,testHands:300,slots:seen,publicCompositionCorrect:priorHit,plusGearCorrect:gearHit,equippedSlots:equipped,equippedPriorCorrect:eqPriorHit,equippedGearCorrect:eqHit}};
mkdirSync('reports',{recursive:true});writeFileSync('reports/numeric-1000.json',JSON.stringify(summary,null,2));writeFileSync('reports/numeric-1000-hands.jsonl',rows.map(r=>JSON.stringify(r)).join('\n')+'\n');console.log(JSON.stringify(summary,null,2));
