import {CARDS,RULES,defaultDeck,judge} from './cards.js';
export {CARDS,RULES,judge};
const clone=x=>structuredClone(x);
const enemy=id=>1-id;
const rule=s=>s.field?.id;
const card=e=>CARDS[e.cardId];
const check=(v,msg)=>{if(!v)throw Error(msg);};
function rand(s){let n=s.rng|0;n^=n<<13;n^=n>>>17;n^=n<<5;s.rng=n>>>0;return s.rng/4294967296;}
function shuffled(s,a){a=[...a];for(let i=a.length-1;i>0;i--){const j=Math.floor(rand(s)*(i+1));[a[i],a[j]]=[a[j],a[i]];}return a;}
function nextRule(s,id){const a=RULES.filter(r=>r.id!==id);return a[Math.floor(rand(s)*a.length)].id;}
function log(s,text){s.log.push(text);if(s.log.length>220)s.log.shift();}
const label=(s,p)=>s.players[p].name;
function mint(s,id,owner){check(CARDS[id],'未知卡牌');return {uid:`e${s.serial++}`,cardId:id,owner};}
export function validateDeck(profession,entries){
 const names=new Map();let count=0;
 for(const e of entries){const c=CARDS[e.id];check(c,'牌不存在');check(Number.isInteger(e.copies)&&e.copies>=1&&e.copies<=3,'每个条目须1—3张');check(['N','U',profession].includes(c.profession),'不能带其他职业牌');check(profession!=='PR'||c.kind!=='support','傲慢不能带辅牌');
 check(profession!=='PR'||!['N04','N08','N13','N18','N20'].includes(c.id),'傲慢不能携带主动过牌或回收主牌');
 const n=(names.get(c.name)||0)+e.copies;check(n<=3,`同名「${c.name}」最多3张`);names.set(c.name,n);count+=e.copies;
 }check(count===35,`卡组需要35张，目前${count}张`);return true;
}
export function createGame({professions=['WR','GL'],decks=null,seed=12873,names=['你','对手']}={}){
 const s={version:2,rng:seed||1,serial:1,players:[],turn:0,actions:0,round:1,pending:null,field:null,rule:'higher',nextRule:null,queue:[],choice:null,phase:'starting',log:[],winner:null,ended:false,fieldSpent:{},actionNo:0};
 for(let id=0;id<2;id++){const profession=professions[id],entries=decks?.[id]||defaultDeck(profession);validateDeck(profession,entries);const p={name:names[id],profession,life:60,armor:0,temp:0,hand:[],deck:[],discard:[],exile:[],sleep:[],used:[],statuses:{},discarded:0,selfHarm:[],returns:[],gifts:[],traded:[],usedAlien:[],acquired:0,started:0,skipDraw:0,debt:[],oaths:0,heroUses:0,decklist:clone(entries),revealed:[],fatigue:0};s.players.push(p);p.deck=shuffled(s,entries.flatMap(e=>Array.from({length:e.copies},()=>mint(s,e.id,id))));p.hand=p.deck.splice(0,5);}
 s.nextRule=nextRule(s,s.rule);s.queue.push({type:'begin'});run(s);return s;
}
function enqueue(s,...jobs){s.queue.unshift(...jobs.filter(Boolean));}
function request(s,owner,title,options,min=1,max=1,then={}){s.choice={owner,title,options,min,max,then};s.phase='choice';}
const option=e=>({id:e.uid,label:card(e).name,cardId:e.cardId});
function pick(s,owner,title,entities,min,max,then){if(!entities.length||max===0)return false;request(s,owner,title,entities.map(option),Math.min(min,entities.length),Math.min(max,entities.length),then);return true;}
function death(s){const dead=s.players.map(p=>p.life<=0);if(dead.some(Boolean)){s.ended=true;s.phase='ended';s.winner=dead.every(Boolean)?'draw':dead[0]?1:0;s.queue=[];s.choice=null;log(s,s.winner==='draw'?'双方生命归零，平局。':`${label(s,s.winner)}获胜。`);return true;}return false;}
function take(p,zone,uid){const i=p[zone].findIndex(e=>e.uid===uid);check(i>=0,'目标已不在该区域');return p[zone].splice(i,1)[0];}
function removeArmor(p,n){const x=Math.min(p.armor,n);p.armor-=x;p.temp=Math.max(0,p.temp-x);return x;}
function selfLoss(s,p,n){const x=Math.min(s.players[p].life,n);s.players[p].life-=x;s.players[p].selfHarm.push({round:s.round,n:x});return x;}
function moveGift(s,from,e){const p=s.players[1-from];s.players[from].gifts.push({round:s.round,n:1});if(rule(s)==='LU-R3'&&p.sleep.length<8){p.sleep.push({...e,due:p.started+1,postponed:false});}else p.hand.push(e);s.players[from].revealed=s.players[from].revealed.filter(u=>u!==e.uid);log(s,`${label(s,from)}交出「${card(e).name}」。`);}
function actualDiscard(s,p,entities){const who=s.players[p];for(const e of entities){if(rule(s)==='EN-R2'&&!s.fieldSpent[`discard${p}`]){s.fieldSpent[`discard${p}`]=true;moveGift(s,p,e);}else{who.discard.push(e);who.discarded++;log(s,`${label(s,p)}弃掉「${card(e).name}」。`);}}}
function discardJob(s,p,entities){
 if(rule(s)==='GL-R5'&&!s.fieldSpent[`save${p}`]&&s.players[p].sleep.length<8&&entities.length){s.fieldSpent[`save${p}`]=true;request(s,p,'可以保护其中一张：它暂存到下回合，不算实际弃牌。也可以不保护。',entities.map(option),0,1,{mode:'saveDiscard',p,entities});return;}
 actualDiscard(s,p,entities);
}
function transformed(effects,support){
 const out=[];for(let e of effects){e={...e};if(['damage','heal','armor'].includes(e.type)){
 if(support==='U01')e.n*=2;if(support==='U02')e.n=Math.floor(e.n/2);
 if(support==='U03'&&e.type==='heal')e.type='armor';else if(support==='U04'&&e.type==='armor')e.type='heal';else if(support==='U05'){if(e.type==='heal')e.type='damage';else if(e.type==='damage')e.type='heal';}
 if(support==='U06'&&e.type==='damage'){out.push({...e,n:Math.floor(e.n/2)},{...e,n:Math.ceil(e.n/2)});continue;}}
 out.push(e);}return out;
}
const recent=(a,r)=>a.filter(x=>x.round>=r-2).reduce((n,x)=>n+x.n,0);
function resolution(s,combo,reply){const p=s.players[combo.owner],o=s.players[1-combo.owner];return {combo,face:judge(combo.rule,combo.number,reply),p,o,recent:recent(p.selfHarm,s.round),returned:recent(p.returns,s.round),given:recent(p.gifts,s.round)};}
function run(s){let guard=0;while(s.queue.length&&!s.choice&&!s.ended){check(++guard<2500,'效果循环过长');job(s,s.queue.shift());}if(!s.ended&&!s.choice&&!s.queue.length)s.phase='action';}
function job(s,j){const p=s.players[j.p];
 switch(j.type){
 case 'begin':{
  const pid=s.turn,p=s.players[pid];s.actionNo++;s.fieldSpent={};p.started++;p.acquired=0;s.round=Math.min(20,Math.floor(s.actions/2)+1);
  if(s.actions>0&&s.actions%6===0){s.rule=s.nextRule;s.nextRule=nextRule(s,s.rule);log(s,`进入第${s.round}回合，数字规则改为「${RULES.find(r=>r.id===s.rule).name}」。已等待的牌不改判定。`);}
  if(rule(s)==='PR-R2'){const n=Math.min(5,20-p.armor);p.armor+=n;p.temp+=n;}
  const due=p.sleep.filter(e=>e.due<=p.started),later=p.sleep.filter(e=>e.due>p.started);p.sleep=later;
  enqueue(s,{type:'normalDraw',p:pid},{type:'ensureMain',p:pid});
  if(due.length){if(rule(s)==='SL-R4'&&due.every(e=>!e.postponed)){request(s,pid,'这些暂存牌到期：现在取回，还是延后一回合并每张治疗3？',[{id:'return',label:'现在取回'},{id:'wait',label:`延后，治疗${3*due.length}`}],1,1,{mode:'due',p:pid,entities:due});}else returnCards(s,pid,due,true);}
  log(s,`第${s.round}回合：轮到${label(s,pid)}。`);return;
 }
 case 'normalDraw':{
  if(s.actions===0)return;if(p.skipDraw>0){p.skipDraw--;log(s,`${label(s,j.p)}偿还一次预支抽牌。`);return;}
  if(rule(s)==='GR-R4'){request(s,j.p,'正常抽1张，还是提前抽3张并跳过随后两次正常抽牌？',[{id:'normal',label:'正常抽1张'},{id:'borrow',label:'预支：抽3张'}],1,1,{mode:'normal',p:j.p});return;}
  if(rule(s)==='SL-R5'){request(s,j.p,'这次正常抽牌，也可以换为眼前生存。',[{id:'normal',label:'抽1张'},{id:'heal',label:'治疗5'},{id:'armor',label:'获得5甲'}],1,1,{mode:'normal',p:j.p});return;}
  enqueue(s,{type:'draw',p:j.p,n:1,normal:true});return;
 }
 case 'draw':{
  if(j.n<=0)return;
  if(!j.normal&&p.profession==='PR'&&j.source===j.p){log(s,'傲慢不能主动额外过牌。');return;}
  const n=j.n;
  if(!j.normal&&!j.processed&&rule(s)==='GR-R1'){
   const candidates=p.deck.splice(0,Math.min(n+2,p.deck.length));if(candidates.length)pick(s,j.p,`选择${Math.min(n,candidates.length)}张加入手牌，其余放到牌库底。`,candidates,Math.min(n,candidates.length),Math.min(n,candidates.length),{mode:'drawSelect',p:j.p,entities:candidates});return;
  }
  if(!j.normal&&!j.processed&&rule(s)==='GL-R2'){enqueue(s,{...j,n:n+2,processed:true},{type:'discard',p:j.p,n:2});return;}
  const got=p.deck.splice(0,n);p.hand.push(...got);if(!j.normal)p.acquired+=got.length;log(s,`${label(s,j.p)}抽到${got.length}张牌${got.length<n?'（牌库不足）':''}。`);
  if(!j.normal&&rule(s)==='GR-R2'&&got.length&&p.sleep.length<8)pick(s,j.p,'这些新抽到的牌可暂存到下回合，每张得2甲，每次最多6。',got,0,Math.min(got.length,8-p.sleep.length),{mode:'drawSleep',p:j.p});
  enqueue(s,{type:'overflow',p:j.p});return;
 }
 case 'overflow':if(p.hand.length>40)pick(s,j.p,'手牌最多40张。选择多出的牌弃掉。',p.hand,p.hand.length-40,p.hand.length-40,{mode:'discard',p:j.p});return;
 case 'ensureMain':{
  if(p.hand.some(e=>canAfford(s,j.p,e.uid)))return;
  p.fatigue++;p.life=Math.max(0,p.life-p.fatigue);log(s,`${label(s,j.p)}没有可打出的主牌，疲劳失去${p.fatigue}生命。`);if(death(s))return;
  const ids=shuffled(s,Object.values(CARDS).filter(c=>c.kind==='main'&&['N',p.profession].includes(c.profession)&&!Object.keys(c.cost).length&&!(p.profession==='PR'&&['N04','N08','N13','N18','N20'].includes(c.id))).map(c=>c.id)).slice(0,3);
  request(s,j.p,'疲劳后，从三张救急主牌中选一张，本回合必须打出。',ids.map(id=>({id,label:CARDS[id].name,cardId:id})),1,1,{mode:'emergency',p:j.p});return;
 }
 case 'resolve':{
  const ctx=resolution(s,j.combo,j.reply);s.resolving={owner:j.combo.owner,combo:j.combo,face:ctx.face,chargeUsed:false,cap:{},oldStatuses:Object.fromEntries(Object.entries(ctx.p.statuses).map(([k,v])=>[k,v.token])),burn:ctx.p.statuses.burn?.layers||0};
  log(s,`${label(s,j.combo.owner)}的「${CARDS[j.combo.card.cardId].name}」：${j.combo.number} 遇到 ${j.reply}，按「${RULES.find(r=>r.id===j.combo.rule).name}」判为${ctx.face==='success'?'成功':'失败'}。`);
  const c=CARDS[j.combo.card.cardId],effects=c.run(ctx)[ctx.face==='success'?0:1];
  enqueue(s,...transformed(effects,j.combo.support?.cardId).map(e=>({...e,p:e.target==='enemy'?1-j.combo.owner:j.combo.owner,source:j.combo.owner,main:true})),{type:'checkpoint'},{type:'after',combo:j.combo,face:ctx.face});return;
 }
 case 'checkpoint':death(s);return;
 case 'damage':case 'loss':{
  let n=Math.max(0,j.n||0);const r=s.resolving,src=j.source??enemy(j.p);
  if(j.type==='damage'&&j.main){n+=s.players[src].statuses.exposed?.layers||0;if(src!==j.p)n+=p.statuses.exposed?.layers||0;if(r&&!r.chargeUsed&&s.players[src].statuses.charge){n+=2*s.players[src].statuses.charge.layers;delete s.players[src].statuses.charge;r.chargeUsed=true;}}
  if(!j.checked&&src!==j.p&&n>0&&r){
   const key=`block${j.p}`;
   if(!r.cap[key]&&((rule(s)==='PR-R4'&&j.type==='damage'&&n<=8)||(rule(s)==='GR-R5'&&((j.type==='loss'&&rule(s)!=='PR-R3')||n>p.armor)))){
    r.cap[key]=true;if(p.hand.length){pick(s,j.p,rule(s)==='PR-R4'?`弃1张牌抵挡这段${n}伤害？可不选。`:'弃1张牌，减少至多5点本次生命伤害？可不选。',p.hand,0,1,{mode:'block',p:j.p,next:{...j,n,main:false,checked:true},full:rule(s)==='PR-R4'});return;}
   }
  }
  if(j.type==='damage'||rule(s)==='PR-R3'){
   if(rule(s)==='LU-R5'&&r&&!r.cap.share&&p.hand.length<s.players[1-j.p].hand.length){r.cap.share=true;n-=removeArmor(s.players[1-j.p],Math.min(3,n));}
   n-=removeArmor(p,n);
  }
  if(j.reduceLife)n=Math.max(0,n-j.reduceLife);
  if(rule(s)==='SL-R1'&&j.type==='damage'&&n>0){p.debt.push({n,due:p.started+1});log(s,`${label(s,j.p)}记下${n}点延迟伤害。`);return;}
  const actual=Math.min(p.life,n);p.life-=actual;if(src===j.p&&actual)p.selfHarm.push({round:s.round,n:actual});log(s,`${label(s,j.p)}失去${actual}生命，剩${p.life}。`);return;
 }
 case 'heal':case 'armor':{
  let kind=j.type,n=Math.max(0,j.n||0),pid=j.p;const r=s.resolving;const cap=r?.cap||{};
  if(!j.raw&&kind==='heal'&&rule(s)==='WR-R1')kind='armor';
  if(!j.raw&&kind==='heal'&&rule(s)==='EN-R4'&&s.players[pid].life>s.players[1-pid].life)pid=1-pid;
  const who=s.players[pid];if(kind==='heal')n=Math.max(0,n-2*(who.statuses.antiheal?.layers||0));
  const actual=Math.min(kind==='heal'?60-who.life:20-who.armor,n);if(kind==='heal')who.life+=actual;else who.armor+=actual;
  log(s,`${label(s,pid)}${kind==='heal'?'恢复':'获得'}${actual}${kind==='heal'?'生命':'护甲'}。`);
  if(!j.raw){const overflow=n-actual;
   if(rule(s)==='WR-R4'&&kind==='armor'&&overflow){const extra=Math.min(overflow,6-(cap.overflow||0));cap.overflow=(cap.overflow||0)+extra;enqueue(s,{type:'damage',p:1-pid,source:pid,n:extra,checked:true});}
   if(rule(s)==='GL-R3'&&kind==='heal'&&overflow){const extra=Math.min(overflow,8-(cap.overheal||0));cap.overheal=(cap.overheal||0)+extra;enqueue(s,{type:'damage',p:1-pid,source:pid,n:extra,checked:true});}
   if(rule(s)==='LU-R1'&&kind==='heal'&&actual){const extra=Math.min(actual,6-(cap.giftArmor||0));cap.giftArmor=(cap.giftArmor||0)+extra;enqueue(s,{type:'armor',p:1-pid,n:extra,raw:true});}
   if(rule(s)==='LU-R2'&&overflow)enqueue(s,{type:kind,p:1-pid,n:overflow,raw:true});
  }return;
 }
 case 'removeArmor':removeArmor(p,j.n);return;
 case 'stealArmor':{const n=removeArmor(s.players[1-j.p],j.n);enqueue(s,{type:'armor',p:j.p,n});return;}
 case 'discard':pick(s,j.p,`选择${Math.min(j.n,p.hand.length)}张手牌弃掉。`,p.hand,Math.min(j.n,p.hand.length),Math.min(j.n,p.hand.length),{mode:'discard',p:j.p});return;
 case 'sleep':pick(s,j.p,'选择要暂存的手牌；暂存期间不能使用。',p.hand,0,Math.min(j.n,8-p.sleep.length,p.hand.length),{mode:'sleep',p:j.p,after:j.after,armor:j.armor||0});return;
 case 'wake':pick(s,j.p,'选择要取回的暂存牌。',p.sleep,0,Math.min(j.n,p.sleep.length),{mode:'wake',p:j.p,armor:j.armor||0,damage:j.damage||0});return;
 case 'postpone':pick(s,j.p,'选择一张暂存牌，延后一回合。',p.sleep,0,1,{mode:'postpone',p:j.p,armor:j.armor});return;
 case 'recover':case 'stealDiscard':{
  const from=j.type==='stealDiscard'?1-j.p:j.p;if(p.profession==='PR'&&j.main){log(s,'傲慢不能主动使用过牌或回收效果。');return;}
  const candidates=s.players[from].discard.filter(e=>card(e).kind==='main'&&(!j.ids||j.ids.includes(e.uid))&&(!j.profession||card(e).profession===j.profession)&&(!j.alien||e.owner!==j.p));
  pick(s,j.p,'选择要取回的普通主牌。',candidates,0,Math.min(j.n,candidates.length),{mode:'recover',p:j.p,from,distinct:!!j.distinct});return;
 }
 case 'status':{
  const old=p.statuses[j.name];p.statuses[j.name]={layers:Math.min(j.name==='echo'?1:3,(old?.layers||0)+j.n),duration:j.duration||3,token:s.serial++};return;
 }
 case 'clear':delete p.statuses[j.name];return;
 case 'after':{
  const r=s.resolving,owner=j.combo.owner,who=s.players[owner];
  if(rule(s)==='EN-R3'){const diff=s.players[0].armor-s.players[1].armor;if(Math.abs(diff)>6){const hi=diff>0?0:1;const n=removeArmor(s.players[hi],3);s.players[1-hi].armor=Math.min(20,s.players[1-hi].armor+n);}}
  const triggers=[];
  if(j.combo.oath){if(j.combo.oath===j.face)triggers.push({type:'armor',p:owner,n:4});else triggers.push({type:'loss',p:owner,source:1-owner,n:2});}
  if(r.burn&&who.statuses.burn?.token===r.oldStatuses.burn)triggers.push({type:'damage',p:owner,source:1-owner,n:r.burn,checked:true});
  enqueue(s,...triggers,{type:'checkpoint'},{type:'archive',combo:j.combo,face:j.face});return;
 }
 case 'archive':{
  if(death(s))return;const owner=j.combo.owner,who=s.players[owner],r=s.resolving;
  for(const [name,token]of Object.entries(r.oldStatuses)){if(who.statuses[name]?.token===token&&--who.statuses[name].duration<=0)delete who.statuses[name];}
  who.discard.push(j.combo.card);if(j.combo.support)who.discard.push(j.combo.support);
  if(j.combo.field){if(j.combo.fieldFace===j.face){if(s.field)s.players[s.field.owner].discard.push(s.field.card);s.field={id:j.combo.field.cardId,owner,card:j.combo.field};log(s,`公共条款改为「${CARDS[s.field.id].name}」：${CARDS[s.field.id].text}`);}else{who.discard.push(j.combo.field);log(s,'附加规则未建立，规则牌已消耗，没有额外惩罚。');}}
  if(j.combo.gift){if(j.combo.giftFace===j.face){moveGift(s,owner,j.combo.gift);enqueue(s,{type:'armor',p:owner,n:1});}else discardJob(s,owner,[j.combo.gift]);}
  const previousField=rule(s);s.resolving=null;
  if(previousField==='PR-R1'){const opts=who.hand.filter(e=>card(e).kind==='main');if(opts.length)pick(s,owner,'可以弃另一张普通主牌，收回刚结算的主牌；也可以不选。',opts,0,1,{mode:'retain',p:owner,target:j.combo.card.uid});}
  if(j.combo.openHand)enqueue(s,{type:'openRecover',p:owner,notName:card(j.combo.card).name});
  enqueue(s,{type:'checkpoint'},{type:'overflow',p:0},{type:'overflow',p:1});return;
 }
 case 'openRecover':pick(s,j.p,'公开手牌的回报：取回一张不同名普通主牌。',p.discard.filter(e=>card(e).kind==='main'&&card(e).name!==j.notName),0,1,{mode:'recover',p:j.p,from:j.p});return;
 case 'activate':s.pending={...j.combo,rule:s.rule};log(s,`「${card(j.combo.card).name}」现在等待对方回应，还没有生效。`);return;
 case 'endAction':{
  const who=s.players[s.turn];if(rule(s)==='WR-R5'){const n=Math.min(4,who.armor,60-who.life);removeArmor(who,n);enqueue(s,{type:'heal',p:s.turn,n},{type:'finishAction'});return;}
  enqueue(s,{type:'finishAction'});return;
 }
 case 'finishAction':{
  const who=s.players[s.turn];
  if(who.temp){who.armor-=Math.min(who.temp,who.armor);who.temp=0;}
  const debts=who.debt.filter(x=>x.due<=who.started);who.debt=who.debt.filter(x=>x.due>who.started);for(const x of debts){who.life=Math.max(0,who.life-x.n);log(s,`延迟伤害到期：${label(s,s.turn)}失去${x.n}生命。`);}
  if(death(s))return;s.actions++;s.turn=1-s.turn;enqueue(s,{type:'begin'});return;
 }
 case 'finish':{
  if(death(s))return;s.ended=true;s.phase='ended';s.pending=null;s.winner=s.players[0].life===s.players[1].life?'draw':s.players[0].life>s.players[1].life?0:1;log(s,`20个完整回合结束，只比较生命。${s.winner==='draw'?'平局':label(s,s.winner)+'获胜'}。`);return;
 }
 default:throw Error(`尚未实现效果：${j.type}`);
 }
}
function returnCards(s,pid,entities,natural=false){const p=s.players[pid];p.hand.push(...entities.map(({due,postponed,...e})=>e));p.returns.push({round:s.round,n:entities.length});p.acquired+=entities.length;log(s,`${label(s,pid)}取回${entities.length}张暂存牌。`);if(natural&&p.profession==='SL'&&entities.length>=2)enqueue(s,{type:'heal',p:pid,n:2});enqueue(s,{type:'overflow',p:pid});}
export function choose(state,ids){const s=clone(state),c=s.choice;check(c,'当前没有选择');check(Array.isArray(ids)&&new Set(ids).size===ids.length&&ids.length>=c.min&&ids.length<=c.max,'选择数量不符');check(ids.every(id=>c.options.some(o=>o.id===id)),'非法选择');const t=c.then,p=s.players[t.p];s.choice=null;s.phase='processing';
 switch(t.mode){
 case 'discard':discardJob(s,t.p,ids.map(id=>take(p,'hand',id)));break;
 case 'saveDiscard':{const kept=t.entities.filter(e=>ids.includes(e.uid));p.sleep.push(...kept.map(e=>({...e,due:p.started+1,postponed:false})));actualDiscard(s,t.p,t.entities.filter(e=>!ids.includes(e.uid)));break;}
 case 'normal':if(ids[0]==='borrow'){p.skipDraw=2;enqueue(s,{type:'draw',p:t.p,n:3,normal:true});}else enqueue(s,ids[0]==='normal'?{type:'draw',p:t.p,n:1,normal:true}:{type:ids[0],p:t.p,n:5});break;
 case 'due':if(ids[0]==='wait'){p.sleep.push(...t.entities.map(e=>({...e,due:p.started+1,postponed:true})));enqueue(s,{type:'heal',p:t.p,n:t.entities.length*3});}else returnCards(s,t.p,t.entities,true);break;
 case 'drawSelect':p.hand.push(...t.entities.filter(e=>ids.includes(e.uid)));p.deck.push(...t.entities.filter(e=>!ids.includes(e.uid)));p.acquired+=ids.length;enqueue(s,{type:'overflow',p:t.p});break;
 case 'drawSleep':case 'sleep':{const es=ids.map(id=>take(p,'hand',id));p.sleep.push(...es.map(e=>({...e,due:p.started+(t.after||1),postponed:false})));enqueue(s,{type:'armor',p:t.p,n:t.mode==='drawSleep'?Math.min(6,ids.length*2):ids.length*t.armor});break;}
 case 'wake':{const es=ids.map(id=>take(p,'sleep',id));returnCards(s,t.p,es);enqueue(s,{type:'armor',p:t.p,n:ids.length*t.armor},ids.length&&t.damage?{type:'damage',p:1-t.p,source:t.p,n:t.damage}:null);break;}
 case 'postpone':if(ids.length){p.sleep.find(e=>e.uid===ids[0]).due++;enqueue(s,{type:'armor',p:t.p,n:t.armor});}break;
 case 'recover':{const es=ids.map(id=>s.players[t.from].discard.find(e=>e.uid===id));if(t.distinct)check(new Set(es.map(e=>card(e).name)).size===es.length,'必须不同名');for(const e of es){take(s.players[t.from],'discard',e.uid);p.hand.push(e);}p.acquired+=es.length;enqueue(s,{type:'overflow',p:t.p});break;}
 case 'block':if(ids.length){discardJob(s,t.p,[take(p,'hand',ids[0])]);if(!t.full)enqueue(s,{...t.next,reduceLife:5});}else enqueue(s,t.next);break;
 case 'emergency':{const e=mint(s,ids[0],t.p);p.hand.push(e);p.emergency=e.uid;break;}
 case 'retain':if(ids.length){discardJob(s,t.p,[take(p,'hand',ids[0])]);if(p.discard.some(e=>e.uid===t.target))p.hand.push(take(p,'discard',t.target));}break;
 default:throw Error('未实现选择');
 }run(s);return s;
}
export function canAfford(s,pid,uid){const p=s.players[pid],e=p.hand.find(e=>e.uid===uid);if(!e||card(e).kind!=='main')return false;const c=card(e);if(p.emergency&&p.emergency!==uid)return false;if(c.cost.discard&&p.hand.length-1<c.cost.discard)return false;if(c.cost.alienExile&&!p.hand.some(x=>x.uid!==uid&&x.owner!==pid))return false;return true;}
export function submit(state,action){const s=clone(state);check(s.phase==='action'&&!s.ended,'现在不能出牌');const pid=s.turn,p=s.players[pid];const {main,number,support=null,field=null,fieldFace='success',materials=[],gift=null,giftFace='success',oath=null,openHand=false}=action;
 check(canAfford(s,pid,main),'主牌无法支付或不在手里');check(Number.isInteger(number)&&number>=1&&number<=20&&!p.used.includes(number),'数字须为尚未使用的1—20');check(['success','failure'].includes(fieldFace)&&['success','failure'].includes(giftFace),'面无效');
 const all=[main,support,field,gift,...materials].filter(Boolean);check(new Set(all).size===all.length&&all.every(id=>p.hand.some(e=>e.uid===id)),'主牌、辅牌、规则、礼物和材料须是不同手牌');
 const c=card(p.hand.find(e=>e.uid===main));if(support)check(p.profession!=='PR'&&card(p.hand.find(e=>e.uid===support)).kind==='support','不是可搭配的辅牌');if(field)check(card(p.hand.find(e=>e.uid===field)).kind==='field','不是规则牌');
 check(materials.length===(c.cost.discard||c.cost.alienExile||0),'材料数量不对');if(c.cost.alienExile)check(materials.every(id=>p.hand.find(e=>e.uid===id).owner!==pid),'必须使用异主材料');
 if(gift)check(p.profession==='LU','只有色欲可以附赠礼物');if(oath)check(p.profession==='PR'&&p.oaths<3&&['success','failure'].includes(oath),'傲慢宣告次数不足');if(openHand)check(rule(s)==='PR-R5'&&!support,'需要对应条款且不能用辅牌');
 const combo={owner:pid,card:take(p,'hand',main),number,support:support?take(p,'hand',support):null,field:field?take(p,'hand',field):null,fieldFace,gift:gift?take(p,'hand',gift):null,giftFace,oath,openHand,materials:[...materials]};
 if(oath)p.oaths++;if(openHand)p.revealed=p.hand.map(e=>e.uid);if(combo.card.owner!==pid&&!p.usedAlien.includes(c.name))p.usedAlien.push(c.name);
 const es=materials.map(id=>take(p,'hand',id));if(c.cost.trade){const names=[...new Set(es.map(e=>card(e).name))];combo.tradeBonus=Math.min(6,names.filter(n=>!p.traded.includes(n)).length*2);p.traded=[...new Set([...p.traded,...names])];log(s,`本笔交割加成${combo.tradeBonus}，材料名字已登记。`);}
 p.used.push(number);p.emergency=null;s.phase='processing';
 const old=s.pending;s.pending=null;
 if(s.actions===39&&old){const finalRule=s.rule;old.rule=finalRule;combo.rule=finalRule;const pairs=[{type:'resolve',combo:old,reply:number},{type:'resolve',combo,reply:old.number}].sort((a,b)=>a.combo.number-b.combo.number||a.combo.owner-b.combo.owner);s.queue.push(...pairs,{type:'finish'});}
 else{s.queue.push(...(old?[{type:'resolve',combo:old,reply:number}]:[]),{type:'activate',combo},{type:'endAction'});}
 if(c.cost.alienExile)p.exile.push(...es);else if(es.length)discardJob(s,pid,es);
 run(s);return s;
}
export function fieldAction(state,{ids=[],amount=0,status=null}={}){
 const s=clone(state);check(s.phase==='action'&&!s.fieldSpent.action,'每个自己的回合只能用一次条款操作');const pid=s.turn,p=s.players[pid],o=s.players[1-pid],r=rule(s);check(r,'没有公共条款');check(new Set(ids).size===ids.length,'不能重复选牌');
 const hand=(n,kind=null)=>{check(ids.length>=1&&ids.length<=n,'选牌数量不符');check(ids.every(id=>p.hand.some(e=>e.uid===id&&(!kind||card(e).kind===kind))),'须选择自己的手牌');return ids.map(id=>take(p,'hand',id));};
 switch(r){
 case 'WR-R2':check(Number.isInteger(amount)&&amount>=1&&amount<=6&&p.life>amount,'付血须1—6且存活');selfLoss(s,pid,amount);enqueue(s,{type:'armor',p:pid,n:amount});break;
 case 'WR-R3':check(p.profession!=='PR'&&p.life>4,'不能主动过牌或生命不足');selfLoss(s,pid,4);enqueue(s,{type:'draw',p:pid,source:pid,n:2});break;
 case 'GL-R1':{const es=hand(2);discardJob(s,pid,es);enqueue(s,{type:'heal',p:pid,n:4*es.length});break;}
 case 'GR-R3':{const es=hand(2);p.deck.push(...es);enqueue(s,{type:'armor',p:pid,n:4*es.length});break;}
 case 'GL-R4':check(ids.length===3&&ids.every(id=>p.discard.some(e=>e.uid===id&&card(e).kind==='main')),'先选两张放逐材料，最后选回收牌');p.exile.push(take(p,'discard',ids[0]),take(p,'discard',ids[1]));p.hand.push(take(p,'discard',ids[2]));break;
 case 'EN-R1':check(ids.length===2&&p.hand.some(e=>e.uid===ids[0]&&card(e).kind==='main')&&o.discard.some(e=>e.uid===ids[1]&&card(e).kind==='main'),'先选自己主牌，再选敌方弃牌');moveGift(s,pid,take(p,'hand',ids[0]));p.hand.push(take(o,'discard',ids[1]));break;
 case 'EN-R5':check(p.armor>=3&&o.statuses[status]&&!p.statuses[status],'需要3甲和自己没有的敌方状态');removeArmor(p,3);p.statuses[status]={...o.statuses[status],token:s.serial++};break;
 case 'SL-R2':{const es=hand(2);check(p.sleep.length+es.length<=8,'暂存区已满');p.sleep.push(...es.map(e=>({...e,due:p.started+2,postponed:false})));enqueue(s,{type:'armor',p:pid,n:es.length*3});break;}
 case 'SL-R3':check(ids.length>=1&&ids.length<=2&&p.armor>=ids.length*3&&ids.every(id=>p.sleep.some(e=>e.uid===id)),'选择至多两张暂存牌，每张支付3甲');removeArmor(p,ids.length*3);returnCards(s,pid,ids.map(id=>take(p,'sleep',id)));break;
 case 'LU-R4':enqueue(s,{type:'draw',p:1-pid,source:pid,n:2},{type:'heal',p:pid,n:8});break;
 default:throw Error('这条规则自动生效，没有主动操作');
 }s.fieldSpent.action=true;enqueue(s,{type:'checkpoint'},{type:'overflow',p:0},{type:'overflow',p:1},{type:'ensureMain',p:pid});run(s);return s;
}
export function view(s,pid){return {version:s.version,turn:s.turn,round:s.round,actions:s.actions,phase:s.phase,ended:s.ended,winner:s.winner,rule:s.rule,nextRule:s.nextRule,field:s.field?{id:s.field.id,owner:s.field.owner}:null,pending:clone(s.pending),log:[...s.log],choice:s.choice?.owner===pid?clone(s.choice):s.choice?{owner:s.choice.owner,title:'对方正在选择'}:null,fieldSpent:clone(s.fieldSpent),players:s.players.map((p,i)=>({name:p.name,profession:p.profession,life:p.life,armor:p.armor,used:[...p.used],handCount:p.hand.length,deckCount:p.deck.length,decklist:clone(p.decklist),hand:i===pid?clone(p.hand):undefined,discard:clone(p.discard),exile:clone(p.exile),sleep:clone(p.sleep),statuses:clone(p.statuses),traded:[...p.traded],discarded:p.discarded,selfHarm:clone(p.selfHarm),gifts:clone(p.gifts),returns:clone(p.returns),usedAlien:[...p.usedAlien],oaths:p.oaths,debt:clone(p.debt),emergency:i===pid?p.emergency:null,revealed:p.hand.filter(e=>p.revealed.includes(e.uid)).map(e=>clone(e))}))};}
