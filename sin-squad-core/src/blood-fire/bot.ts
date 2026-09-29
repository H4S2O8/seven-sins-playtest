import type { Style } from "../ai/agents.js";
import { BASES, BY_ID, type Card } from "./content.js";
import type { Plan } from "./battle.js";
import { BloodFireTable } from "./table.js";

/** Opponent sees public purchases and field, and its own secret base/plan. It never reads player plans or base. */
export class BloodFireBot {
  private pulse=0;
  constructor(private style:Style,private seed:number){this.seed>>>=0;}
  private rand(){this.seed=(this.seed*1664525+1013904223)>>>0;return this.seed/4294967296;}
  private cardValue(c:Card,owned:string[]){const friends=owned.map(id=>BY_ID[id]);let n=c.attack*1.15+(c.kind==="ranged"?1.1:0)+(13-c.interval)*.24;const faction=friends.filter(x=>x.faction===c.faction).length;n+=faction*.8;
    if(c.faction==="blood"&&friends.some(x=>x.id==="B01"||x.id==="B03"||x.id==="B05"))n+=1.1;
    if(c.faction==="fire"&&friends.some(x=>x.id==="F01"||x.id==="F08"))n+=1.2;
    if(c.faction==="name"&&friends.some(x=>x.id==="N01"||x.id==="N02"))n+=1;
    if(c.kind==="melee"&&friends.filter(x=>x.kind==="melee").length>=2)n-=.7;
    return n;
  }
  draftBid(t:BloodFireTable){const own=t.picked[1],best=Math.max(...t.pair.map(c=>this.cardValue(c,own))),difference=Math.abs(this.cardValue(t.pair[0],own)-this.cardValue(t.pair[1],own));let n=Math.round(1+difference*1.7+(best-4)*.45);if(this.style==="aggressive")n+=2;if(this.style==="cautious")n=Math.max(0,n-1);if(this.style==="bluff"&&this.rand()<.25)n+=3;return Math.min(t.stacks[1],Math.max(0,n));}
  pick(t:BloodFireTable):0|1{return this.cardValue(t.pair[0],t.picked[1])>=this.cardValue(t.pair[1],t.picked[1])?0:1;}
  configure(t:BloodFireTable):Plan[]{const cards=t.picked[1].map(id=>BY_ID[id]);const ranked=cards.map((c,i)=>({c,i,front:c.kind==="melee"?3:0,heal:c.faction==="blood"?1:0})).sort((a,b)=>b.front-a.front||b.c.attack-a.c.attack);const hp=[10,8,6];const plans=ranked.map(({c},slot)=>({id:c.id,hp:hp[slot],enabled:true,target:slot as 0|1|2,choice:0 as 0|1}));for(let i=0;i<3;i++){const c=cards.find(x=>x.id===plans[i].id)!;if(c.target==="ally")plans[i].target=(c.faction==="blood"?0:c.id==="N02"?2:i) as 0|1|2;if(c.target==="enemy")plans[i].target=(c.id==="F01"||c.id==="F04"?2:0) as 0|1|2;plans[i].choice=(c.id==="F06"&&t.picked[1].some(x=>x==="F01")?0:c.id==="N10"&&t.base[1]==="P04"?1:0) as 0|1;}
    return plans;}
  fieldBid(t:BloodFireTable){const f=t.fieldCandidate.id,own=t.picked[1].map(id=>BY_ID[id]),foe=t.picked[0].map(id=>BY_ID[id]);let fit=0;if(["E03","E04","E05"].includes(f))fit=own.filter(c=>c.faction==="fire").length-foe.filter(c=>c.faction==="fire").length;if(["E09","E10","E11"].includes(f))fit=own.filter(c=>c.faction==="blood").length-foe.filter(c=>c.faction==="blood").length;if(["E12","E13","E17","E20"].includes(f))fit=own.filter(c=>c.faction==="name").length-foe.filter(c=>c.faction==="name").length;const n=Math.round(1+Math.max(0,fit)*2+(this.style==="aggressive"?2:0));return Math.min(t.stacks[1],n);}
  adopt(t:BloodFireTable){if(!t.currentField)return true;return t.fieldCandidate.id!==t.currentField&&this.fieldBid(t)>1;}
  private strength(ids:string[],base?:string,field?:string|null){let n=ids.reduce((sum,id)=>sum+this.cardValue(BY_ID[id],ids.filter(x=>x!==id)),0);const factions=ids.map(id=>BY_ID[id].faction);if(factions.filter(x=>x==="blood").length>=2)n+=2;if(factions.filter(x=>x==="fire").length>=2)n+=2;if(factions.filter(x=>x==="name").length>=2)n+=1.5;if(base==="P04"&&factions.includes("blood"))n+=2;if(base==="P03"&&factions.includes("name"))n+=2;if(field&&["E03","E04","E05"].includes(field)&&factions.includes("fire"))n+=1.5;return n;}
  betAction(t:BloodFireTable):{kind:"check"|"call"|"raise"|"fold";amount?:number}{const owed=Math.max(0,t.bet[0]-t.bet[1]);const own=this.strength(t.picked[1],t.base[1],t.currentField),foe=this.strength(t.picked[0],undefined,t.currentField);const advantage=own-foe;const potOdds=owed/(t.pot+owed+1);const bluff=this.style==="bluff"&&this.rand()<.19;this.pulse++;
    if(owed>0){if(owed>Math.max(5,t.stacks[1]*.12)&&advantage<-(2+potOdds*8)&&!bluff)return{kind:"fold"};return{kind:"call"};}
    if(this.pulse<3&&advantage>2.5&&t.stacks[1]>5)return{kind:"raise",amount:Math.min(t.stacks[1],Math.max(2,Math.round(advantage/2)+2))};
    if(this.style==="aggressive"&&advantage>0&&this.pulse<3&&t.stacks[1]>5)return{kind:"raise",amount:3};
    if(bluff&&t.stacks[1]>6&&this.pulse<3)return{kind:"raise",amount:4};return{kind:"check"};}
}
