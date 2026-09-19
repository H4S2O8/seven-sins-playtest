// This module receives view(state, player), never the private engine state.
import {CARDS, judge} from './cards.js?v=e38f7686abea';
const recent=(xs,round)=>(xs||[]).filter(x=>x.round>=round-2).reduce((n,x)=>n+x.n,0);
const publicPlayer=p=>({...p,hand:p.hand||Array.from({length:p.handCount},()=>({})),acquired:p.acquired||0});
function faceValue(v,owner,combo,face,support){
 const p=publicPlayer(v.players[owner]),o=publicPlayer(v.players[1-owner]);
 let effects;try{effects=CARDS[combo.card.cardId].run({p,o,combo,recent:recent(p.selfHarm,v.round),returned:recent(p.returns,v.round),given:recent(p.gifts,v.round)})[face==='success'?0:1];}catch{return 0;}
 let score=0;
 for(const x of effects){let {type,n=0}=x;const target=x.target==='enemy'?o:p,sign=x.target==='enemy'?-1:1;
 if(['damage','heal','armor'].includes(type)){
 if(support==='U01')n*=2;if(support==='U02')n=Math.floor(n/2);
 if(support==='U03'&&type==='heal')type='armor';else if(support==='U04'&&type==='armor')type='heal';else if(support==='U05')type=type==='damage'?'heal':type==='heal'?'damage':type;
 }
 if(type==='heal'&&v.field?.id==='WR-R1')type='armor';
 if(type==='heal')score+=sign*Math.min(n,60-target.life)*1.2;
 if(type==='armor')score+=sign*Math.min(n,20-target.armor)*.65;
 if(type==='damage'||type==='loss'){const loss=Math.max(0,n-(type==='damage'?target.armor:0));score-=sign*(loss*1.25+Math.min(n,target.armor)*.45+(loss>=target.life?150:0));}
 if(type==='draw')score+=sign*Math.min(n,target.deckCount)*1.4;
 if(type==='discard')score-=sign*Math.min(n,target.hand.length)*1.4;
 if(type==='removeArmor')score-=sign*Math.min(n,target.armor)*.7;
 if(type==='stealArmor')score+=Math.min(n,o.armor)*1.2;
 if(type==='status')score+=(x.name==='charge'?sign:-sign)*n*2;
 if(type==='wake')score+=Math.min(n,p.sleep.length)*2;
 if(type==='sleep')score+=p.hand.length>8?2:0;
 if(type==='recover')score+=Math.min(n,p.discard.length)*2;
 if(type==='stealDiscard')score+=Math.min(n,o.discard.length)*3;
 }
 return score;
}
export function chooseAI(v){
 const c=v.choice,p=v.players[c.owner];if(!c?.options)return [];
 const mode=c.then?.mode;
 if(mode==='mulligan'){
  let keptMain=0,keptSupport=0;return c.options.filter(o=>{const card=CARDS[o.cardId];if(card.kind==='main'&&!card.cost.alienExile&&!(card.cost.discard>=3)){keptMain++;return false;}if(card.kind==='support'&&keptSupport++===0)return false;return true;}).map(o=>o.id);
 }
 if(mode==='normal')return [p.life<45&&c.options.some(o=>o.id==='heal')?'heal':'normal'];
 if(mode==='due')return ['return'];
 let n=c.min;
 if(['recover','wake','drawSleep','sleep','postpone','retain','block','saveDiscard'].includes(mode))n=c.max;
 if(mode==='sleep'&&p.handCount<5)n=0;
 const opts=[...c.options];if(['discard','retain','block'].includes(mode))opts.sort((a,b)=>(CARDS[a.cardId]?.kind==='main'?1:0)-(CARDS[b.cardId]?.kind==='main'?1:0));
 const result=[],names=new Set();for(const o of opts){if(c.then?.distinct&&names.has(o.label))continue;result.push(o.id);names.add(o.label);if(result.length>=n)break;}
 return n===0?[]:result;
}
export function actionAI(v,pid=v.turn){
 const p=v.players[pid],o=v.players[1-pid],numbers=Array.from({length:20},(_,i)=>i+1).filter(n=>!p.used.includes(n));
 const replyNumbers=Array.from({length:20},(_,i)=>i+1).filter(n=>!o.used.includes(n));
 const field=p.hand.find(e=>CARDS[e.cardId].kind==='field'&&e.cardId!==v.field?.id);
 let best=null,bestScore=-Infinity;
 for(const e of p.hand){const c=CARDS[e.cardId];if(c.kind!=='main'||p.emergency&&p.emergency!==e.uid)continue;
 const materialPool=p.hand.filter(x=>x.uid!==e.uid&&(!c.cost.alienExile||x.owner!==pid)).sort((a,b)=>(CARDS[a.cardId].kind==='main'?1:0)-(CARDS[b.cardId].kind==='main'?1:0));
 const count=c.cost.discard||c.cost.alienExile||0;if(materialPool.length<count)continue;const materials=materialPool.slice(0,count).map(x=>x.uid);
 const supports=[null,...p.hand.filter(x=>CARDS[x.cardId].kind==='support'&&!materials.includes(x.uid)&&p.profession!=='PR')];
 for(const number of numbers)for(const support of supports){
 const combo={owner:pid,card:e,number,materials,tradeBonus:c.cost.trade?Math.min(6,new Set(materialPool.slice(0,count).map(e=>CARDS[e.cardId].name).filter(n=>!p.traded.includes(n))).size*2):0};
 const a=faceValue(v,pid,combo,'success',support?.cardId),b=faceValue(v,pid,combo,'failure',support?.cardId);
 const possible=new Set((replyNumbers.length?replyNumbers:[number]).map(n=>judge(v.rule,number,n)));
 const future=possible.size===1?(possible.has('success')?a:b):Math.min(a,b)*.7+Math.max(a,b)*.3;
 const previous=v.pending?-faceValue(v,1-pid,v.pending,judge(v.pending.rule,v.pending.number,number),v.pending.support?.cardId):0;
 const score=previous+future-count*.8-(support?1:0)-Math.abs(number-10.5)*.015;
 if(score>bestScore){bestScore=score;best={main:e.uid,number,materials,support:support?.uid||null};if(field&&!materials.includes(field.uid))Object.assign(best,{field:field.uid,fieldFace:a>=b?'success':'failure'});if(p.profession==='PR'&&p.oaths<3&&possible.size===1)best.oath=[...possible][0];}
 }
 }
 if(!best)throw Error('电脑没有找到合法主牌，请导出对局记录。');return best;
}
