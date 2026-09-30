import { BASES, CARDS, FIELDS, type Card } from "./content.js";
import { battle, type Plan, type Result, type Side } from "./battle.js";

export type Phase="draft"|"arrange"|"field"|"field-choice"|"bet"|"battle"|"over";
type BetStage="opening"|"field"|"final";
export class BloodFireTable {
  phase:Phase="draft";
  stacks:[number,number]=[100,100];
  pot=0;
  round=0;
  fieldRound=0;
  betStage:BetStage="opening";
  currentField:string|null=null;
  fieldCandidate=FIELDS[0];
  pair:[Card,Card]=[CARDS[0],CARDS[1]];
  picked:[string[],string[]]=[[],[]];
  base:[string,string]=[BASES[0].id,BASES[1].id];
  plans:[Plan[],Plan[]]=[[],[]];
  planLocked:[boolean,boolean]=[false,false];
  bids:[number|null,number|null]=[null,null];
  fieldChoices:[boolean|null,boolean|null]=[null,null];
  bet:[number,number]=[0,0];
  betTurn:0|1=0;
  checks=0;
  lastRaise=2;
  result:Result|null=null;
  folded:0|1|null=null;
  auctionWinner:0|1=0;
  fieldWinner:0|1=0;
  noFieldWinner=false;
  log:string[]=[];
  private seed:number;
  constructor(seed=Math.floor(Math.random()*2147483647)) {this.seed=seed>>>0;this.base=[BASES[this.rand(BASES.length)].id,BASES[this.rand(BASES.length)].id];this.pay(0,10);this.pay(1,10);this.deal();this.fieldCandidate=FIELDS[this.rand(FIELDS.length)];}
  private rand(n:number){this.seed=(1664525*this.seed+1013904223)>>>0;return this.seed%n;}
  private deal(){this.pair=[CARDS[this.rand(CARDS.length)],CARDS[this.rand(CARDS.length)]];}
  private pay(side:0|1,n:number){if(!Number.isInteger(n)||n<0||n>this.stacks[side])throw Error("筹码不足或出价无效");this.stacks[side]-=n;this.pot+=n;}
  bid(side:0|1,n:number){if(this.phase!=="draft"&&this.phase!=="field")throw Error("现在不能竞价");if(this.bids[side]!==null)throw Error("已经密封出价");if(!Number.isInteger(n)||n<0||n>this.stacks[side])throw Error("无效出价");this.bids[side]=n;if(this.bids[0]===null||this.bids[1]===null)return;const [a,b]=this.bids as [number,number];this.bids=[null,null];if(this.phase==="draft"){
    if(a===0&&b===0){this.deal();this.log.push("双方跳过，换一组人物");return;}
    const winner:0|1 = a===b?(this.round%2) as 0|1:a>b?0:1;
    this.auctionWinner=winner;const price=[a,b][winner];this.pay(winner,price);this.log.push(`${winner===0?"你":"对手"}用 ${price} 筹码赢得先选权`);this.phase="arrange";return;
  }
    if(a===0&&b===0){this.fieldChoices=[false,false];this.noFieldWinner=true;this.planLocked=[false,false];this.log.push("双方放弃新场地，保留当前效果；请各自锁定布阵");this.phase="field-choice";return;}
    const winner:0|1 = a===b?(this.fieldRound%2) as 0|1:a>b?0:1;this.fieldWinner=winner;this.pay(winner,[a,b][winner]);this.fieldChoices=[null,null];this.phase="field-choice";this.log.push(`${winner===0?"你":"对手"}赢得本轮场地选择权`);
  }
  choose(side:0|1,index:0|1){if(this.phase!=="arrange"||side!==this.auctionWinner)throw Error("尚未轮到你选牌");const other=1-side as 0|1;this.picked[side].push(this.pair[index].id);this.picked[other].push(this.pair[1-index as 0|1].id);
    this.round++;this.log.push(`${this.round}/3 轮人物入队`);if(this.round===3){this.phase="bet";this.fieldRound=0;this.fieldCandidate=FIELDS[this.rand(FIELDS.length)];this.startBet();this.plans=this.picked.map(ids=>ids.map((id,i)=>({id,hp:8,enabled:false,target:i as 0|1|2,choice:0}))) as [Plan[],Plan[]];}else{this.phase="draft";this.deal();}}
  configure(side:0|1,plans:Plan[]){if(!["bet","field-choice","field"].includes(this.phase)||this.planLocked[side])throw Error("阵容已锁定");if(plans.length!==3||plans.some(p=>!Number.isInteger(p.hp)||p.hp<4||p.hp>12)||plans.reduce((a,p)=>a+p.hp,0)!==24||plans.some(p=>!this.picked[side].includes(p.id)))throw Error("分血或人物不合法");const a=[...this.picked[side]].sort().join(),b=plans.map(p=>p.id).sort().join();if(a!==b)throw Error("人物与采购不符");this.plans[side]=structuredClone(plans);}
  fieldDecision(side:0|1,adopt:boolean){if(this.phase!=="field-choice"||this.noFieldWinner||this.fieldWinner!==side)throw Error("你没有场地决定权");if(this.fieldChoices[side]!==null)throw Error("已经锁定场地选择");this.fieldChoices[side]=adopt;this.planLocked[side]=true;this.tryLockPlans();}
  lockPlan(side:0|1){if(this.phase!=="field-choice")throw Error("现在不能锁定布阵");if(this.planLocked[side])throw Error("布阵已经锁定");this.planLocked[side]=true;this.tryLockPlans();}
  private tryLockPlans(){if(!this.planLocked[0]||!this.planLocked[1])return;if(!this.noFieldWinner){const winChoice=this.fieldChoices[this.fieldWinner]!;if(winChoice)this.currentField=this.fieldCandidate.id;this.log.push(`${this.fieldWinner===0?"你":"对手"}${winChoice?"采用新场地":"保留当前场地"}`);}this.noFieldWinner=false;this.fieldChoices=[null,null];this.fieldRound++;this.betStage="field";this.lockPlans();}
  private lockPlans(){this.phase="bet";this.bet=[0,0];this.checks=0;this.betTurn=0;this.lastRaise=2;}
  private startBet(){this.bet=[0,0];this.checks=0;this.betTurn=0;this.lastRaise=2;this.betStage="opening";}
  wager(side:0|1,action:"check"|"call"|"raise"|"fold",amount=0){if(this.phase!=="bet"||this.betTurn!==side)throw Error("未到下注时机");const owed=this.bet[1-side as 0|1]-this.bet[side];if(action==="fold"){this.folded=side;this.phase="over";this.stacks[1-side as 0|1]+=this.pot;this.pot=0;this.log.push(`${side===0?"你":"对手"}弃牌`);return;}
    if(action==="check"){if(owed>0)throw Error("必须跟注或弃牌");this.checks++;if(this.checks>=2){this.finishBet();return;}this.betTurn=1-side as 0|1;return;}
    if(action==="call"){if(owed===0)throw Error("没有下注可跟");const paid=Math.min(owed,this.stacks[side]);this.pay(side,paid);this.bet[side]+=paid;this.checks=2;this.finishBet();return;}
    if(action==="raise"){const total=owed+amount;const paid=Math.min(total,this.stacks[side]);if(paid<=owed)throw Error("筹码不足以形成加注");if(amount<this.lastRaise&&paid<this.stacks[side])throw Error(`最小加注为 ${this.lastRaise}，但可全押`);this.pay(side,paid);this.bet[side]+=paid;this.lastRaise=Math.max(this.lastRaise,paid-owed);this.checks=0;this.betTurn=1-side as 0|1;return;}
  }
  private finishBet(){
    const unmatched=Math.abs(this.bet[0]-this.bet[1]);if(unmatched){const side=this.bet[0]>this.bet[1]?0:1;this.stacks[side]+=unmatched;this.pot-=unmatched;this.bet[side]-=unmatched;}
    if(this.stacks[0]===0||this.stacks[1]===0){this.resolveBattle();return;}
    if(this.betStage==="opening"){this.planLocked=[false,false];this.fieldCandidate=FIELDS[this.rand(FIELDS.length)];this.phase="field";return;}
    if(this.betStage==="field"&&this.fieldRound<3){this.planLocked=[false,false];this.fieldCandidate=FIELDS[this.rand(FIELDS.length)];this.phase="field";return;}
    if(this.betStage==="field"){this.betStage="final";this.phase="bet";this.startBet();this.betStage="final";return;}
    this.resolveBattle();
  }
  private resolveBattle(){this.phase="battle";this.result=battle([{units:this.plans[0],base:this.base[0]},{units:this.plans[1],base:this.base[1]}] as [Side,Side],this.currentField);this.phase="over";if(this.result.winner===null){this.stacks[0]+=Math.floor(this.pot/2);this.stacks[1]+=Math.ceil(this.pot/2);}else this.stacks[this.result.winner]+=this.pot;this.pot=0;}
}
