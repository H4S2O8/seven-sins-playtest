import { battle, type Plan } from "../src/blood-fire/battle.js";
import { BASES, CARDS, FIELDS } from "../src/blood-fire/content.js";
const p=(id:string,enabled:boolean,slot:0|1|2=0):Plan=>({id,hp:8,enabled,target:slot,choice:0});
const summary=(r:ReturnType<typeof battle>)=>({winner:r.winner,events:r.events.filter(e=>e.kind!=="skill").map(e=>`${e.tick}/${e.kind}/${e.source}/${e.target}/${e.amount}/${e.label}`)});
const dead:string[]=[];
for(const c of CARDS){let changes=0;for(const [a,b] of [["B01","F01"],["B03","F08"],["N02","N07"],["B07","N10"]]){
  const run=(enabled:boolean)=>battle([{base:"P04",units:[p(c.id,enabled,0),p(a,true,1),p(b,true,2)]},{base:"P02",units:[p("B05",true,0),p("F01",true,1),p("N04",true,2)]}],"E11");
  if(JSON.stringify(summary(run(true)))!==JSON.stringify(summary(run(false))))changes++;
}if(!changes)dead.push(`${c.id} ${c.name}`);}
const idle:string[]=[];
for(const f of FIELDS){let changes=0;for(const base of BASES.slice(0,4)){
  const sides=[{base:base.id,units:[p("B01",true),p("F01",true,1),p("N04",true,2)]},{base:"P02",units:[p("F08",true),p("B03",true,1),p("N02",true,2)]}] as const;
  if(JSON.stringify(summary(battle(structuredClone(sides) as never,f.id)))!==JSON.stringify(summary(battle(structuredClone(sides) as never,null))))changes++;
}if(!changes)idle.push(`${f.id} ${f.name}`);}
console.log(JSON.stringify({skillNoObservedDifference:dead,fieldNoObservedDifference:idle},null,2));
