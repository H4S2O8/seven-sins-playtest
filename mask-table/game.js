import {makeBoard,cloneBoard,executeCard,tick,placements,getCardTargets,rng} from './engine.js';
import {CARD_LIBRARY} from './catalog.js';
import {generateRule,evaluateRule,generateBet,evaluateBet} from './rules.js';

export const START_CHIPS=60, TARGET_CHIPS=120, ANTE=3, MAX_ROUNDS=8;
const deep=x=>JSON.parse(JSON.stringify(x));
function random(s){s.draws++;return rng((s.seed+Math.imul(s.draws,2654435761))>>>0)();}
function pick(s,a){return a[Math.floor(random(s)*a.length)];}
function shuffle3(s,a){let pool=[...a],out=[];while(out.length<3&&pool.length)out.push(pool.splice(Math.floor(random(s)*pool.length),1)[0]);return out;}
export function addLog(s,text,kind='info',side=null){s.log.push({id:++s.logId,text,kind,side,round:s.round});if(s.log.length>100)s.log.shift();}
let instanceCache=null;
export function allCardInstances(){
 if(instanceCache)return instanceCache;
 const names=['上','右','下','左','中'],seen=new Set();instanceCache=[];
 for(const card of CARD_LIBRARY)for(const p of legalPlacements(card)){
  const signature=card.id+'@'+[...p.targets].sort((a,b)=>a-b).join('.');
  if(seen.has(signature))continue;seen.add(signature);
  instanceCache.push({...deep(card),id:signature,baseId:card.id,targets:[...p.targets],shape:'fixed',name:card.name+(p.targets.length?' · '+p.targets.map(i=>names[i]).join(''):'')});
 }
 return instanceCache;
}
function offerCards(s){
 const available=allCardInstances();
 const chosen=shuffle3(s,available);s.seenCards.push(...chosen.map(c=>c.id));return chosen.map(deep);
}
export function newSession(seed=Date.now(),options={}){
 const s={version:1,seed:seed>>>0,draws:0,players:[0,1].map(i=>({name:i?'对手 · 乌鸦':'你',chips:START_CHIPS,board:null,history:[],observations:[],known:Array(5).fill(null),committed:0,turns:0,inspected:false,bet:null})),house:200,fees:0,escrow:0,pot:0,hand:0,round:1,active:0,phase:'draft',log:[],logId:0,simple:!!options.simple,roundLimit:MAX_ROUNDS};
 return startHand(s);
}
export function startHand(s){
 if(s.players.some(p=>p.chips<=0||p.chips>=(s.targetChips||TARGET_CHIPS))){s.phase='matchOver';return s;}
 s.hand++;s.round=1;s.active=(s.hand-1)%2;s.phase='draft';s.checkStreak=0;s.pending=null;s.result=null;s.publicActions=[];s.log=[];s.pot=0;s.seenCards=[];s.startChips=s.players.map(p=>p.chips);
 s.rule=generateRule(()=>random(s),{simple:s.simple});
 const ante=Math.min(ANTE,...s.players.map(p=>p.chips));
 for(const p of s.players){p.chips-=ante;p.committed=ante;s.pot+=ante;p.board=null;p.history=[];p.observations=[];p.known=Array(5).fill(null);p.turns=0;p.inspected=false;p.bet=null;p.rerolls=0;}
 s.mainOffers=[0,1].map(()=>Array.from({length:3},()=>makeBoard(Array.from({length:5},()=>Math.floor(random(s)*10)))));
 s.offers=[[],[]];s.betOffers=Array.from({length:3},()=>generateBet(()=>random(s)));s.betRerolls=0;s.usedOffer=false;
 addLog(s,`第${s.hand}局 · 双方各下底${ante}枚。先读规则，再选一张五位主牌。`);
 return s;
}
export function moneyTotal(s){return s.players.reduce((n,p)=>n+p.chips,0)+s.pot+s.fees+s.house+s.escrow;}
export function callCost(s,who){return Math.max(0,s.players[1-who].committed-s.players[who].committed);}
export function maxRaise(s,who){return Math.max(0,s.players[who].chips-callCost(s,who));}
function transferBet(s,who,amount){if(!Number.isInteger(amount)||amount<0||s.players[who].chips<amount)throw new Error('筹码不足');s.players[who].chips-=amount;s.players[who].committed+=amount;s.pot+=amount;}
export function reroll(s,who=0){
 if(s.phase!=='draft'&&(s.phase!=='play'||s.active!==who))throw new Error('现在不能重刷');
 const p=s.players[who],cost=p.rerolls+1;
 if(p.chips<cost+callCost(s,who))throw new Error('需要保留足够筹码跟注');
 p.chips-=cost;s.fees+=cost;p.rerolls++;
 if(s.phase==='draft')s.mainOffers[who]=Array.from({length:3},()=>makeBoard(Array.from({length:5},()=>Math.floor(random(s)*10))));else s.offers[who]=offerCards(s);
 addLog(s,`${p.name}花${cost}枚重刷三选一。重刷费不进入奖池。`,'draft',who);
}
function rankBoard(rule,board,randomFn){let total=0;for(let i=0;i<12;i++){let other=makeBoard(Array.from({length:5},()=>Math.floor(randomFn()*10)));let r=evaluateRule(rule,board,other);total+=r.winner===0?1:r.winner===null?.5:0;}return total;}
export function chooseMain(s,index){
 if(s.phase!=='draft'||!s.mainOffers[0][index])throw new Error('请选择三张主牌中的一张');
 s.players[0].board=cloneBoard(s.mainOffers[0][index]);
 let best=0,bestScore=-Infinity;
 const aiSeed=Math.floor(random(s)*0xffffffff);
 s.mainOffers[1].forEach((b,i)=>{const score=rankBoard(s.rule,b,rng(aiSeed));if(score>bestScore){bestScore=score;best=i;}});
 s.players[1].board=cloneBoard(s.mainOffers[1][best]);
 s.players.forEach(p=>p.rerolls=0);s.mainOffers=[[],[]];s.phase='play';s.offers=[offerCards(s),offerCards(s)];
 addLog(s,'双方主牌已扣下。你只看见自己的数字；对手的材料与出牌位置公开。','draft');
}
export function legalPlacements(card){
 if(card.targets)return [{anchor:card.targets[0]??4,rotation:0,targets:[...card.targets]}];
 if(card.shape==='fixed')return [{anchor:4,rotation:0,targets:[]}];
 return placements(card.shape||'single');
}
function appendHistory(s,who,entry){s.players[who].history.push(deep(entry));s.publicActions.push({who,...deep(entry)});}
function updateKnowledge(s,actor,entry){
 const viewer=s.players[1-actor],rev=s.players[actor].history.length;
 // Facts remain in observations. Mark snapshots historical unless a permutation can be safely tracked.
 const card=entry.type==='card'?entry.card:null;
 const swaps={swap_ud:[0,2],swap_lr:[3,1],swap_uc:[0,4],swap_rc:[1,4],swap_dc:[2,4],swap_lc:[3,4]};
 const pair=card&&swaps[card.operationId];
 if(pair){const [a,b]=pair;[viewer.known[a],viewer.known[b]]=[viewer.known[b],viewer.known[a]];for(const k of viewer.known)if(k&&k.revision===rev-1)k.revision=rev;}
}
function applyPublicCard(s,who,card,targets){
 const plain=s.players[who].board.cells.every(c=>!c.attribute&&!c.keywords.length&&!Object.keys(c.statuses).length);
 const result=executeCard(s.players[who].board,card,targets);
 appendHistory(s,who,{type:'card',cardId:card.id,card:deep(card),targets:[...targets]});updateKnowledge(s,who,plain?{type:'card',cardId:card.id,card,targets}:{type:'changed'});
 s.lastAnimation={who,targets:[...targets],card:deep(card),events:who===0?result.events:[],nonce:++s.logId};
 const pos=['上','右','下','左','中'];addLog(s,`${s.players[who].name}打出「${card.name}」${targets.length?' → '+targets.map(i=>pos[i]).join('、'):''}。${card.description}`,'card',who);
 return result;
}
function endTurn(s,who){
 s.players[who].turns++;s.usedOffer=false;
 if(s.checkStreak>=2){settle(s,'双方连续只跟注／过牌，自动开牌');return;}
 if(s.players.every(p=>p.turns>=s.roundLimit)){settle(s,`本局已完成${s.roundLimit}轮，开牌结算`);return;}
 if(s.players.some(p=>p.chips===0)&&callCost(s,0)===0&&callCost(s,1)===0){settle(s,'筹码已全下，开牌结算');return;}
 s.active=1-who;s.round=Math.min(...s.players.map(p=>p.turns))+1;
 const p=s.players[s.active];
 if(p.turns>0){const result=tick(p.board);appendHistory(s,s.active,{type:'tick'});updateKnowledge(s,s.active,{type:'tick'});if(result.events?.length)addLog(s,`${p.name}的回合开始：持续状态已触发。`,'status',s.active);}
 p.rerolls=0;s.offers[s.active]=offerCards(s);
}
export function playCard(s,who,offerIndex,placement,raise=1){
 if(s.phase!=='play'||s.active!==who)throw new Error('还没轮到你');
 const card=s.offers[who][offerIndex];if(!card)throw new Error('请选择本轮三选一中的牌');
 const legal=legalPlacements(card).find(p=>p.anchor===placement.anchor&&p.rotation===placement.rotation);
 if(!legal)throw new Error('这个形状放不下，请换位置或旋转');
 if(!Number.isInteger(raise)||raise<1||raise>maxRaise(s,who))throw new Error('加注超出双方可支付的额度');
 const payment=callCost(s,who)+raise;transferBet(s,who,payment);
 applyPublicCard(s,who,card,legal.targets);s.checkStreak=0;
 addLog(s,`${s.players[who].name}补齐并投入${payment}枚，其中加注${raise}枚。`,'bet',who);endTurn(s,who);
}
export function call(s,who){
 if(s.phase!=='play'||s.active!==who)throw new Error('还没轮到你');
 const amount=Math.min(callCost(s,who),s.players[who].chips);transferBet(s,who,amount);s.checkStreak++;
 if(s.players.some(p=>p.chips===0)){settle(s,'全下跟注，开牌结算');return;}
 addLog(s,`${s.players[who].name}${amount?`跟注${amount}枚`:'过牌'}，没有修改盘面。`,'bet',who);endTurn(s,who);
}
export function canOpen(s,who){return s.phase==='play'&&s.active===who&&s.players.every(p=>p.turns>=1);}
export function open(s,who){if(!canOpen(s,who))throw new Error('双方至少各行动一次后，轮到你时才可以开牌');transferBet(s,who,Math.min(callCost(s,who),s.players[who].chips));settle(s,`${s.players[who].name}跟注并要求开牌`);}
export function fold(s,who){if(s.phase!=='play'||s.active!==who)throw new Error('现在不能弃牌');settle(s,`${s.players[who].name}弃牌`,1-who);}
export function settle(s,reason,foldWinner=null){
 const matched=Math.min(...s.players.map(p=>p.committed));
 for(const p of s.players){const excess=p.committed-matched;if(excess){p.chips+=excess;p.committed-=excess;s.pot-=excess;addLog(s,`${p.name}未被跟注的${excess}枚退回。`);}}
 const comparison=evaluateRule(s.rule,s.players[0].board,s.players[1].board);
 const isFold=foldWinner!==null,winner=isFold?foldWinner:comparison.winner;
 const pot=s.pot,payout=[0,0];
 if(winner===null){s.players.forEach((p,i)=>{payout[i]=p.committed;p.chips+=payout[i];});}else{s.players[winner].chips+=pot;payout[winner]=pot;}
 s.pot=0;
 const bets=[];
 s.players.forEach((p,i)=>{if(!p.bet)return;const def=p.bet.card,stake=p.bet.stake;let hit=null;if(isFold)p.chips+=stake;else{hit=evaluateBet(def,s.players[1-i].board);if(hit){p.chips+=2*stake;s.house-=stake;}else s.house+=stake;}s.escrow-=stake;bets.push({who:i,name:def.name,stake,hit});});
 s.result={reason,isFold,winner,comparison:isFold?null:comparison,pot,payout,bets,net:s.players.map((p,i)=>p.chips-s.startChips[i])};s.phase='result';s.pending=null;
 addLog(s,`${reason}。${winner===null?'平局，退回双方主池下注':s.players[winner].name+'赢得奖池'+pot+'枚'}。`,'result');
}
export function maxSideBet(s,who){
 return Math.max(0,s.players[who].chips-callCost(s,who));
}
export function rerollSideBets(s,who=0){
 if(s.phase!=='play'||s.active!==who||s.players[who].turns!==0||s.players[who].bet)throw new Error('现在不能刷新赌注牌');
 const cost=(s.betRerolls||0)+1;
 if(s.players[who].chips<cost+callCost(s,who))throw new Error('需要保留跟注筹码');
 s.players[who].chips-=cost;s.fees+=cost;s.betRerolls=cost;s.betOffers=Array.from({length:3},()=>generateBet(()=>random(s)));
 addLog(s,`${s.players[who].name}花${cost}枚刷新赌注三选一。`,'draft',who);
}
export function placeSideBet(s,who,id,stake){
 if(s.phase!=='play'||s.active!==who||s.players[who].turns!==0||s.players[who].bet)throw new Error('赌注牌只能在本局自己的第一次行动前使用一张');
 if(!s.betOffers.some(b=>b.id===id)||!Number.isInteger(stake)||stake<1||stake>maxSideBet(s,who))throw new Error('押注必须在当前可支付额度内');
 const p=s.players[who];
 if(p.chips<stake+callCost(s,who))throw new Error('可用筹码不足');
 p.chips-=stake;s.escrow+=stake;p.bet={id,stake,card:deep(s.betOffers.find(b=>b.id===id))};addLog(s,`${p.name}贴出赌注「${p.bet.card.name}」，押${stake}枚。命中含本金返还${stake*2}枚，未中归零。`,'sidebet',who);
}
export function requestInspection(s,requester,index){
 if(s.phase!=='play'||s.active!==requester||s.players[requester].inspected||!Number.isInteger(index)||index<0||index>4)throw new Error('本局每人只能发起一次查验，且必须在自己回合');
 s.players[requester].inspected=true;
 const owner=1-requester,max=Math.min(s.players[0].chips,s.players[1].chips);
 s.pending={requester,owner,index,max,price:null};
 if(owner===0)s.phase='quote';else{
  const cell=s.players[owner].board.cells[index];
  const relevance=(s.rule.scope||[0,1,2,3,4]).includes(index)?1:.4;
  const price=Math.max(0,Math.min(max,Math.round((1+s.pot*.16)*relevance+(Math.abs(cell.value-5)>3?1:0))));
  s.pending.price=price;s.phase='inspectChoice';
 }
 addLog(s,`${s.players[requester].name}申请查验${s.players[owner].name}的${['上','右','下','左','中'][index]}位。报价方不能拒绝这次二选一。`,'inspect');
}
export function quoteInspection(s,price){if(s.phase!=='quote'||!Number.isInteger(price)||price<0||price>s.pending.max)throw new Error('报价必须是双方当前付得起的整数');s.pending.price=price;s.phase='inspectChoice';}
export function resolveInspection(s,choice){
 if(s.phase!=='inspectChoice'||!['pay','receive'].includes(choice))throw new Error('请选择付钱查验或收钱让对方保密');
 const {requester,owner,index,price}=s.pending,a=s.players[requester],b=s.players[owner];if(price===null)throw new Error('还未报价');
 if(choice==='pay'){if(a.chips<price)throw new Error('筹码不足');a.chips-=price;b.chips+=price;const fact={index,value:b.board.cells[index].value,revision:b.history.length};a.observations.push(fact);a.known[index]={...fact};addLog(s,`${a.name}支付${price}枚，查到${b.name}的${['上','右','下','左','中'][index]}位。数字只对查验者可见。`,'inspect');}
 else {if(b.chips<price)throw new Error('筹码不足');b.chips-=price;a.chips+=price;addLog(s,`${a.name}选择收取${price}枚，${b.name}保留秘密。`,'inspect');}
 s.pending=null;s.phase='play';
}
export function publicAIView(s,who=1){
 const p=s.players[who],other=s.players[1-who];
 return {who,board:cloneBoard(p.board),rule:deep(s.rule),chips:p.chips,opponentChips:other.chips,pot:s.pot,callCost:callCost(s,who),maxRaise:maxRaise(s,who),turns:p.turns,opponentTurns:other.turns,canOpen:canOpen(s,who),inspected:p.inspected,offers:deep(s.offers[who]),history:deep(other.history),observations:deep(p.observations),known:deep(p.known),seed:(s.seed+s.draws*17)>>>0};
}
export function sampleOpponent(view,count=24){
 const randomFn=rng(view.seed||1),result=[],fallback=[];
 const observations=view.observations||[];
 for(let attempt=0;attempt<Math.max(100,count*8)&&result.length<count;attempt++){
  const b=makeBoard(Array.from({length:5},()=>Math.floor(randomFn()*10)));let valid=true;
  for(let rev=0;rev<=view.history.length;rev++){
   for(const obs of observations.filter(o=>o.revision===rev))if(b.cells[obs.index].value!==obs.value)valid=false;
   if(rev===view.history.length)break;
   const h=view.history[rev];if(h.type==='tick')tick(b);else{const card=h.card||CARD_LIBRARY.find(c=>c.id===h.cardId);if(card)executeCard(b,card,h.targets);}
  }
  if(valid)result.push(b);if(fallback.length<count)fallback.push(b);
 }
 if(!result.length){for(const b of fallback){for(const obs of observations.filter(o=>o.revision===view.history.length))b.cells[obs.index].value=obs.value;result.push(b);}}
 while(result.length<count&&result.length)result.push(cloneBoard(result[result.length%Math.max(1,result.length)]));
 return result;
}
export function estimateStrength(rule,board,samples){return samples.reduce((sum,b)=>{const r=evaluateRule(rule,board,b);return sum+(r.winner===0?1:r.winner===null?.5:0);},0)/Math.max(1,samples.length);}
export function chooseAIAction(view){
 const randomFn=rng(view.seed^0xa5a5a5),samples=sampleOpponent(view,20);
 const strength=estimateStrength(view.rule,view.board,samples);
 if(view.callCost>view.chips)return {type:'fold'};
 if(view.canOpen&&((strength>.78&&randomFn()>.18)||view.maxRaise===0))return {type:'open'};
 if(strength<.22&&view.callCost>=Math.max(3,view.chips*.15)&&randomFn()>.2)return {type:'fold'};
 let best=null,score=-Infinity;
 if(view.maxRaise>=1)for(let i=0;i<view.offers.length;i++)for(const placement of legalPlacements(view.offers[i])){
  const copy=cloneBoard(view.board);executeCard(copy,view.offers[i],placement.targets);
  const immediate=estimateStrength(view.rule,copy,samples);
  const future=cloneBoard(copy);tick(future);const futureScore=estimateStrength(view.rule,future,samples);
  const utility=immediate*.8+futureScore*.2;
  if(utility>score){score=utility;best={type:'card',offerIndex:i,placement,raise:1};}
 }
 if(best&&(score>strength+.035||view.turns===0||randomFn()<.18)){
  best.raise=Math.min(view.maxRaise,score>.7?3:1);return best;
 }
 if(view.canOpen&&randomFn()<.4)return {type:'open'};
 return {type:'call'};
}
export function runAITurn(s){
 if(s.phase!=='play'||s.active!==1)return;
 const view=publicAIView(s,1),randomFn=rng(view.seed^0x34567);
 if(!view.inspected&&view.turns>=1&&view.pot>=10&&randomFn()<.3){
  const scope=s.rule.scope||[0,1,2,3,4];requestInspection(s,1,scope[Math.floor(randomFn()*scope.length)]??4);return;
 }
 const action=chooseAIAction(view);
 if(action.type==='card')playCard(s,1,action.offerIndex,action.placement,action.raise);
 else if(action.type==='open')open(s,1);else if(action.type==='fold')fold(s,1);else call(s,1);
}
export function answerAIInspection(s){
 if(s.phase!=='inspectChoice'||s.pending.requester!==1)return;
 const value=Math.max(1,s.pot*.13),price=s.pending.price;
 resolveInspection(s,price<=value?'pay':'receive');
}
