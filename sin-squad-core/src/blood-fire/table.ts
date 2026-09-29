import { BASES, CARDS, FIELDS, type Card } from "./content.js";
import { battle, type Plan, type Result, type Side } from "./battle.js";

export type Phase="draft"|"arrange"|"field"|"field-choice"|"bet"|"battle"|"over";
export class BloodFireTable {
  phase:Phase="draft";
  stacks:[number,number]=[90,90];
  pot=20;
  round=0;
  fieldRound=0;
  currentField:string|null=null;
  fieldCandidate=FIELDS[0];
  pair:[Card,Card]=[CARDS[0],CARDS[1]];
  picked:[string[],string[]]=[[],[]];
  base:[string,string]=[BASES[0].id,BASES[1].id];
  plans:[Plan[],Plan[]]=[[],[]];
  bids:[number|null,number|null]=[null,null];
  bet:[number,number]=[0,0];
  betTurn:0|1=0;
  checks=0;
  result:Result|null=null;
  folded:0|1|null=null;
  auctionWinner:0|1=0;
  fieldWinner:0|1=0;
  log:string[]=[];
  private seed:number;
  constructor(seed=Math.floor(Math.random()*2147483647)) {this.seed=seed>>>0;this.base=[BASES[this.rand(BASES.length)].id,BASES[this.rand(BASES.length)].id];this.deal();this.fieldCandidate=FIELDS[this.rand(FIELDS.length)];}
  private rand(n:number){this.seed=(1664525*this.seed+1013904223)>>>0;return this.seed%n;}
  private deal(){this.pair=[CARDS[this.rand(CARDS.length)],CARDS[this.rand(CARDS.length)]];}
  private pay(side:0|1,n:number){if(!Number.isInteger(n)||n<0||n>this.stacks[side])throw Error("筹码不足或出价无效");this.stacks[side]-=n;this.pot+=n;}
  bid(side:0|1,n:number){if(this.phase!=="draft"&&this.phase!=="field")throw Error("现在不能竞价");if(this.bids[side]!==null)throw Error("已经密封出价");if(!Number.isInteger(n)||n<0||n>this.stacks[side])throw Error("无效出价");this.bids[side]=n;if(this.bids[0]===null||this.bids[1]===null)return;const [a,b]=this.bids as [number,number];this.bids=[null,null];if(this.phase==="draft"){
    if(a===0&&b===0){this.deal();this.log.push("双方跳过，换一组人物");return;}
    const winner:0|1 = a===b?(this.round%2) as 0|1:a>b?0:1;
    this.auctionWinner=winner;const price=[a,b][winner];this.pay(winner,price);this.log.push(`${winner===0?"你":"对手"}用 ${price} 筹码赢得先选权`);this.phase="arrange";return;
  }
    const winner=a===b?null:a>b?0:1;if(winner!==null){this.pay(winner,[a,b][winner]);this.fieldWinner=winner;this.phase="field-choice";this.log.push(`${winner===0?"你":"对手"}花 ${[a,b][winner]} 筹码赢得场地决定权`);}else{this.log.push("场地保留");this.startBet();}
  }
  choose(side:0|1,index:0|1){if(this.phase!=="arrange"||side!==this.auctionWinner)throw Error("尚未轮到你选牌");const other=1-side as 0|1;this.picked[side].push(this.pair[index].id);this.picked[other].push(this.pair[1-index as 0|1].id);
    this.round++;this.log.push(`${this.round}/3 轮人物入队`);if(this.round===3){this.phase="field";this.fieldRound=0;this.fieldCandidate=FIELDS[this.rand(FIELDS.length)];this.plans=[this.picked[0].map((id,i)=>({id,hp:8,enabled:false,target:i as 0|1|2,choice:0})),this.picked[1].map((id,i)=>({id,hp:8,enabled:false,target:i as 0|1|2,choice:0}))];}else{this.phase="draft";this.deal();}}
  configure(side:0|1,plans:Plan[]){if(!["field","field-choice","bet"].includes(this.phase))throw Error("阵容已锁定");if(plans.length!==3||plans.reduce((a,p)=>a+p.hp,0)!==24||plans.some(p=>p.hp<4||p.hp>12||!this.picked[side].includes(p.id)))throw Error("分血或人物不合法");const a=[...this.picked[side]].sort().join(),b=plans.map(p=>p.id).sort().join();if(a!==b)throw Error("人物与采购不符");this.plans[side]=structuredClone(plans);}
  fieldDecision(side:0|1,adopt:boolean){if(this.phase!=="field-choice"||this.fieldWinner!==side)throw Error("无权决定场地");if(adopt)this.currentField=this.fieldCandidate.id;this.log.push(`${side===0?"你":"对手"}${adopt?"采用新场地":"保留旧场地"}`);this.startBet();}
  private startBet(){this.phase="bet";this.betTurn=0;this.bet=[0,0];this.checks=0;}
  wager(side:0|1,action:"check"|"call"|"raise"|"fold",amount=0){if(this.phase!=="bet"||this.betTurn!==side)throw Error("未到下注时机");const owed=this.bet[1-side as 0|1]-this.bet[side];if(action==="fold"){this.folded=side;this.phase="over";this.stacks[1-side as 0|1]+=this.pot;this.log.push(`${side===0?"你":"对手"}弃牌`);return;}
    if(action==="check"){if(owed>0)throw Error("必须跟注或弃牌");this.checks++;if(this.checks>=2){this.finishBet();return;}}
    if(action==="call"){const paid=Math.min(owed,this.stacks[side]);this.pay(side,paid);this.bet[side]+=paid;this.checks=2;this.finishBet();return;}
    if(action==="raise"){const total=owed+amount;if(amount<2||total>this.stacks[side])throw Error("加注至少2，且不能超过筹码");this.pay(side,total);this.bet[side]+=total;this.checks=0;}
    this.betTurn=1-side as 0|1;
  }
  private finishBet(){if(this.fieldRound<2){this.fieldRound++;this.fieldCandidate=FIELDS[this.rand(FIELDS.length)];this.phase="field";this.bet=[0,0];this.checks=0;}else{this.phase="battle";this.result=battle([{units:this.plans[0],base:this.base[0]},{units:this.plans[1],base:this.base[1]}] as [Side,Side],this.currentField);this.phase="over";if(this.result.winner===null){this.stacks[0]+=Math.floor(this.pot/2);this.stacks[1]+=Math.ceil(this.pot/2);}else this.stacks[this.result.winner]+=this.pot;}}
}
