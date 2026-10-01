// 回合级攻防演练引擎。实现 README / 审计语法 v0.2 的可执行子集：
// 100点构筑、5点启动费+填数、每轮每方一次行动、先手锁定后手应对、
// 20刻时间轴（同刻：安装→移除→伤害/治疗→净值结算）、因果链每词实例一次、
// 倒下休整一轮后满血复出、全队同时倒下判负。未覆盖的语义见演练报告。
import {mitigationDamage} from './参考结算器.mjs';

export const DEFAULT_RULES={fee:5,frenzy:1.25,aoeSharedRoot:false,reviveGuard:false,maxRounds:10};

// ---------- 构筑 ----------
// layout: even 均分；tank 一核其余1血；duo 两核其余1血。技能宿主放在核心上。
export function makeSide(name,layout,numbersUsed,skills,keywords={}){
  const hpPool=100-numbersUsed;
  if(hpPool<5)return null;
  let hps;
  if(layout==='even'){const b=Math.floor(hpPool/5);hps=[0,1,2,3,4].map(i=>b+(i<hpPool-5*b?1:0));}
  else if(layout==='tank')hps=[hpPool-4,1,1,1,1];
  else if(layout==='duo'){const c=hpPool-3;hps=[Math.ceil(c/2),Math.floor(c/2),1,1,1];}
  else throw new Error('layout');
  if(hps.some(h=>h<1))return null;
  const units=hps.map((h,i)=>({id:i,maxHp:h,hp:h,downRound:null,
    firstBlock:!!keywords.firstBlock&&i===0,fbSpent:false,unyielding:!!keywords.unyielding&&i===0,unySpent:false,
    immuneFrenzy:!!keywords.immuneFrenzy&&i===0,reflectOnce:!!keywords.reflectOnce&&i===0,rfSpent:false}));
  // 宿主：第一个技能放0号，第二个放 duo 时的1号，否则仍放0号（每张卡可装多个技能）。
  skills.forEach((s,i)=>{s.host=(layout==='duo'&&i===1)?1:(layout==='even'?i%5:0);});
  return {name,units,ap:0,skills,layout};
}

let uidSeq=0;
const alive=u=>u.hp>0&&u.downRound===null;
export function skillCost(s,rules){
  switch(s.type){
    case 'strike':return rules.fee+s.N*(s.repeat||1)+(s.extraN||0);
    case 'heal':return rules.fee+s.H;
    case 'healEngine':return rules.fee+s.H;
    case 'mit':return rules.fee+s.R+(s.T??20);
    case 'watch':return rules.fee+(s.N||0);
    case 'remove':return rules.fee;
    default:throw new Error(s.type);
  }
}
export function skillBudget(s){
  // 构筑时占用预算的数字：重复只填一次；持续秒数由发动时选择，按最大值20计入构筑。
  switch(s.type){
    case 'strike':return s.N+(s.extraN||0);
    case 'heal':case 'healEngine':return s.H;
    case 'mit':return s.R+20;
    case 'watch':return s.N||0;
    default:return 0;
  }
}

// ---------- 行动展开 ----------
// 返回该方本轮可选行动（含“不行动”）。目标候选收敛到有决策意义的几个。
export function options(state,me,rules,first=true,enemyOpt=null){
  const S=state.sides[me],E=state.sides[1-me],opts=[{skill:null}];
  const foes=E.units.filter(alive),friends=S.units.filter(alive);
  if(!foes.length)return opts;
  const hostSet=new Set(E.skills.map(s=>s.host));
  const pickFoes=()=>{
    const c=new Map();
    const low=[...foes].sort((a,b)=>a.hp-b.hp||a.id-b.id)[0];c.set(low.id,low);
    const hosts=foes.filter(u=>hostSet.has(u.id)).sort((a,b)=>a.hp-b.hp);if(hosts[0])c.set(hosts[0].id,hosts[0]);
    const high=[...foes].sort((a,b)=>b.hp-a.hp)[0];c.set(high.id,high);
    return [...c.values()];
  };
  for(const s of S.skills){
    const host=S.units[s.host];
    if(!alive(host)||S.ap<skillCost(first||s.type!=='mit'?s:{...s,T:1},rules))continue;
    if(s.type==='strike'&&s.target==='single'){for(const u of pickFoes())opts.push({skill:s,target:u.id});}
    else if((s.type==='heal'||s.type==='mit')&&s.target==='single'){
      const c=new Set([s.host,[...friends].sort((a,b)=>a.hp-b.hp)[0]?.id]);
      for(const id of c)if(id!==undefined&&alive(S.units[id]))opts.push({skill:s,target:id});
    }else if(s.type==='remove'){
      // 只能点选已公开的对方限时效果：即本轮先手已宣告的监听器/状态。
      if(!first&&enemyOpt?.skill&&(['watch','healEngine'].includes(enemyOpt.skill.type)||enemyOpt.skill.spread||enemyOpt.skill.chainDown||enemyOpt.skill.frenzyEnemies))opts.push({skill:s});
    }else opts.push({skill:s});
  }
  return opts;
}

// 把一方选择的行动转为时间轴项目。first=是否先手（先手看不到对方，窗口需覆盖全轮）。
function schedule(state,me,opt,first,enemyItems,rules){
  const s=opt.skill;if(!s)return [];
  const S=state.sides[me],E=state.sides[1-me];
  S.ap-=skillCost(s,rules);
  // 后手的即时效果：若先手开了窗口（减伤）或先手在0刻治疗，就错开到窗口后。
  let t=0;
  if(!first&&(s.type==='strike'||s.type==='healEngine')){
    const winEnd=Math.max(0,...enemyItems.filter(i=>i.kind==='mit').map(i=>i.from+i.T));
    const healAt=enemyItems.some(i=>i.kind==='heal')?1:0;
    t=Math.max(healAt,winEnd<=19?winEnd:0);
  }
  const enemyAttackTicks=enemyItems.filter(i=>i.kind==='damage').map(i=>i.t);
  const items=[],src={side:me,unit:s.host};
  const foes=()=>E.units.filter(alive).map(u=>u.id);
  switch(s.type){
    case 'strike':{
      const targets=s.target==='all'?foes():[opt.target];
      const amt=s.N*(s.mult||1);
      const lead=s.frenzyEnemies?[{kind:'status',t,side:1-me,units:foes(),status:'frenzy',src}]:[];
      items.push(...lead);
      if(s.spread)items.push({kind:'watch',t,side:me,wtype:'spread',observe:{side:1-me,units:'all'},every:true,src});
      if(s.chainDown)items.push({kind:'watch',t,side:me,wtype:'chainDown',observe:{side:1-me,units:'all'},every:true,src,N:s.extraN});
      if(s.split){
        const [a,b]=s.split;const other=foes().filter(id=>id!==opt.target).sort((x,y)=>E.units[x].hp-E.units[y].hp)[0];
        items.push({kind:'damage',t,side:1-me,targets:[opt.target],amount:a*(s.mult||1),src});
        if(other!==undefined)items.push({kind:'damage',t:Math.min(19,t+1),side:1-me,targets:[other],amount:b*(s.mult||1),src});
        break;
      }
      for(let k=0;k<(s.repeat||1);k++)items.push({kind:'damage',t:Math.min(19,t+k),side:1-me,targets,amount:amt,src,copy:s.copy&&k===0});
      break;
    }
    case 'heal':{
      const targets=s.target==='all'?S.units.filter(alive).map(u=>u.id):[opt.target];
      // 应对型治疗与来袭伤害同刻（净值）；先手只能放0刻。
      const tt=first?0:(enemyAttackTicks.length?Math.min(...enemyAttackTicks):0);
      items.push({kind:'heal',t:tt,side:me,targets,amount:s.H,src});break;
    }
    case 'healEngine':{
      items.push({kind:'watch',t,side:me,wtype:'healToDamage',observe:{side:me,units:'all'},every:true,src,hitAll:s.hitAll!==false});
      items.push({kind:'heal',t,side:me,targets:s.own==='self'?[s.host]:S.units.filter(alive).map(u=>u.id),amount:s.H,src});break;
    }
    case 'mit':{
      const targets=s.target==='all'?S.units.filter(alive).map(u=>u.id):[opt.target];
      let from=0,T=20;
      if(!first){T=1;if(enemyAttackTicks.length){from=Math.min(...enemyAttackTicks);T=Math.max(...enemyAttackTicks)-from+1;}}
      S.ap+=20-T; // 实付秒数：按20预扣，退回未用部分（构筑按20计）
      if(S.ap<0)throw new Error('AP不足');
      items.push({kind:'mit',t:from,from,T,side:me,targets,R:s.R,src});break;
    }
    case 'watch':{
      const units=s.owners==='all'?'all':[s.host];
      items.push({kind:'watch',t:0,side:me,wtype:s.wtype,observe:{side:me,units},every:!!s.every,src,mult:s.mult||1});break;
    }
    case 'remove':{const tgt=enemyItems.find(i=>i.kind==='watch')||enemyItems.find(i=>i.kind==='status');
      if(tgt)items.push({kind:'remove',t:tgt.t,uid:tgt.uid,side:me});break;}
  }
  for(const i of items)if(i.kind==='watch'||i.kind==='status')i.uid=++uidSeq;
  return items;
}

// ---------- 结算一轮 ----------
export function resolveRound(state,acts,rules){
  // acts: [{me,opt,first}] 按先后。后手的 opt 已经看过先手项目。
  const log=[];
  let items=[];
  for(const a of acts){const it=schedule(state,a.me,a.opt,a.first,items.filter(i=>i.side!==undefined),rules);items.push(...it);}
  const watchers=[],mits=[],statuses=[];
  const onRoot=new Map();
  const extra=[];// 延后生成（复制、连杀）的直接事件
  let winner=null;
  for(let t=0;t<20&&winner===null;t++){
    const now=items.filter(i=>i.t===t).concat(extra.filter(i=>i.t===t));
    if(!now.length)continue;
    for(const i of now){
      if(i.kind==='watch')watchers.push({...i,spent:false});
      if(i.kind==='mit')for(const u of i.targets)mits.push({side:i.side,unit:u,R:i.R,from:i.from,to:i.from+i.T});
      if(i.kind==='status')for(const u of i.units){const U=state.sides[i.side].units[u];
        if(i.status==='frenzy'&&U.immuneFrenzy){log.push(`免疫狂振:${i.side}.${u}`);continue;}
        statuses.push({side:i.side,unit:u,status:i.status,uid:i.uid});}
    }
    for(const i of now.filter(i=>i.kind==='remove')){
      const k=watchers.findIndex(w=>w.uid===i.uid);if(k>=0){log.push(`移除:${watchers[k].wtype}`);watchers.splice(k,1);}
      const s=statuses.findIndex(w=>w.uid===i.uid);if(s>=0){log.push('移除:狂振');statuses.splice(s,1);}
    }
    // 直接事件：每个目标一个实例；默认每实例独立因果链。
    const ledger=state.sides.map(S=>S.units.map(u=>({dmg:0,heal:0,v:u.hp})));
    const pending=[];let rootN=0;
    for(const i of now.filter(i=>i.kind==='damage'||i.kind==='heal')){
      const shared=`r${t}-${++rootN}`;
      for(const u of i.targets)pending.push({kind:i.kind,side:i.side,unit:u,amount:i.amount,src:i.src,root:rules.aoeSharedRoot?shared:`${shared}-${u}`,copy:i.copy});
    }
    let guard=0;
    const hasFrenzy=(side,unit)=>statuses.some(s=>s.side===side&&s.unit===unit&&s.status==='frenzy');
    const used=root=>{if(!onRoot.has(root))onRoot.set(root,new Set());return onRoot.get(root);};
    const observes=(w,side,unit)=>w.observe.side===side&&(w.observe.units==='all'||w.observe.units.includes(unit));
    const fire=(w,root)=>{const u=used(root);if(u.has(w.uid)||w.spent)return false;u.add(w.uid);if(!w.every)w.spent=true;return true;};
    while(pending.length){
      if(++guard>5000)throw new Error('因果链未终止');
      let e=pending.shift();
      const U0=state.sides[e.side].units[e.unit];if(!U0||U0.downRound!==null)continue;
      // 待结算改写：转移、转为。
      for(let hop=0;hop<20;hop++){
        const w=watchers.find(w=>(w.wtype==='redirect'||w.wtype==='convert')&&observes(w,e.side,e.unit)&&e.kind==='damage'&&!used(e.root).has(w.uid)&&!w.spent);
        if(!w)break;fire(w,e.root);
        if(w.wtype==='redirect'){
          const S2=state.sides[e.src.side].units[e.src.unit];
          if(!S2||S2.downRound!==null){log.push('转移失败:来源不在场');continue;}
          log.push(`转移:${e.side}.${e.unit}->${e.src.side}.${e.src.unit}`);
          e={...e,side:e.src.side,unit:e.src.unit,src:{side:e.side,unit:e.unit}};
        }else{log.push(`转为治疗:${e.side}.${e.unit}`);e={...e,kind:'heal'};}
      }
      const U=state.sides[e.side].units[e.unit],L=ledger[e.side][e.unit];
      if(e.kind==='heal'){
        const act=Math.max(0,Math.min(e.amount,U.maxHp-L.v));
        L.heal+=e.amount;L.v=Math.min(U.maxHp,L.v+e.amount);
        if(act>0){
          if(U.reviveHeal){} // 保留位
          for(const w of watchers.filter(w=>w.wtype==='healToDamage'&&observes(w,e.side,e.unit)))
            if(fire(w,e.root)){const foe=1-w.side;
              for(const f of state.sides[foe].units.filter(alive).sort((x,y)=>x.hp-y.hp).slice(0,w.hitAll?5:1))pending.push({kind:'damage',side:foe,unit:f.id,amount:act,src:w.src,root:e.root});
              log.push(`治疗引爆:${act}x全体`);}
        }
        continue;
      }
      let amt=e.amount;
      if(hasFrenzy(e.src.side,e.src.unit))amt=Math.ceil(amt*rules.frenzy);
      if(hasFrenzy(e.side,e.unit))amt=Math.ceil(amt*rules.frenzy);
      const pct=Math.min(20,mits.filter(m=>m.side===e.side&&m.unit===e.unit&&m.from<=t&&t<m.to).reduce((a,m)=>a+m.R,0));
      let dmg=mitigationDamage(amt,0,pct);
      if(dmg>0&&U.firstBlock&&!U.fbSpent){U.fbSpent=true;dmg=0;log.push(`首挡:${e.side}.${e.unit}`);}
      const act=Math.max(0,Math.min(dmg,L.v));
      L.dmg+=dmg;L.v-=dmg;
      if(act>0){
        if(U.reflectOnce&&!U.rfSpent){U.rfSpent=true;pending.push({kind:'damage',side:e.src.side,unit:e.src.unit,amount:1,src:{side:e.side,unit:e.unit},root:e.root});}
        for(const w of watchers.filter(w=>w.wtype==='reflect'&&observes(w,e.side,e.unit)))
          if(fire(w,e.root)){pending.push({kind:'damage',side:e.src.side,unit:e.src.unit,amount:act*w.mult,src:{side:e.side,unit:e.unit},root:e.root});log.push(`回敬:${act*w.mult}`);}
        for(const w of watchers.filter(w=>w.wtype==='spread'&&observes(w,e.side,e.unit)))
          if(fire(w,e.root)){const others=state.sides[e.side].units.filter(u=>alive(u)&&u.id!==e.unit).sort((a,b)=>ledger[e.side][a.id].v-ledger[e.side][b.id].v);
            if(others[0]){pending.push({kind:'damage',side:e.side,unit:others[0].id,amount:act,src:w.src,root:e.root});log.push(`扩散:${act}`);}}
        if(e.copy){const others=state.sides[e.side].units.filter(u=>alive(u)&&u.id!==e.unit).sort((a,b)=>a.hp-b.hp);
          if(others[0])extra.push({kind:'damage',t:Math.min(19,t+1),side:e.side,targets:[others[0].id],amount:act,src:e.src});}
      }
    }
    // 净值结算
    const downs=[];
    state.sides.forEach((S,si)=>S.units.forEach((u,ui)=>{
      if(u.downRound!==null)return;const L=ledger[si][ui];
      if(!L.dmg&&!L.heal)return;
      let hp=Math.max(0,Math.min(u.maxHp,u.hp-L.dmg+L.heal));
      if(hp===0&&u.unyielding&&!u.unySpent){u.unySpent=true;hp=1;log.push(`不屈:${si}.${ui}`);}
      u.hp=hp;if(hp===0){u.downRound=state.round;downs.push([si,ui]);}
    }));
    for(const [si] of downs)for(const w of watchers.filter(w=>w.wtype==='chainDown'&&w.observe.side===si))
      if(!w.spent&&t<19){const tg=state.sides[si].units.filter(alive).map(u=>u.id);if(tg.length)extra.push({kind:'damage',t:t+1,side:si,targets:tg,amount:w.N,src:w.src});if(!w.every)w.spent=true;}
    const lost=state.sides.map(S=>S.units.every(u=>!alive(u)));
    if(lost[0]&&lost[1])winner='draw-wipe';else if(lost[0])winner=1;else if(lost[1])winner=0;
  }
  state.pendingWatchers=[]; // 监听器只维持本轮
  return {winner,log};
}

// ---------- 对局 ----------
function clone(s){return {round:s.round,pendingWatchers:[...(s.pendingWatchers||[])],
  sides:s.sides.map(S=>({...S,units:S.units.map(u=>({...u})),skills:S.skills}))};}
function evalFor(state,me,winner){
  if(winner===me)return 1e5;if(winner===1-me)return -1e5;if(winner==='draw-wipe')return 0;
  const v=S=>S.units.reduce((a,u)=>a+(alive(u)?12+u.hp*0.6:(u.downRound===state.round?-3:4)),0)
    +Math.max(0,...S.units.filter(alive).map(u=>u.hp))*1.5+S.ap*0.1;
  return v(state.sides[me])-v(state.sides[1-me])-120*wipeRisk(state,me)+120*wipeRisk(state,1-me);
}
// 下轮对方能否一击全灭（忽略本方应对，仅作局面风险估计）。
function wipeRisk(state,me){
  const S=state.sides[me],E=state.sides[1-me],r=state.round+1,ap=E.ap+10*r;
  const next=S.units.filter(u=>alive(u)||(u.downRound!==null&&u.downRound+2<=r)).map(u=>alive(u)?u.hp:u.maxHp);
  const eAlive=id=>{const u=E.units[id];return alive(u)||(u.downRound!==null&&u.downRound+2<=r);};
  let best=0;
  for(const s of E.skills){
    if(!eAlive(s.host)||skillCost(s,DEFAULT_RULES)>ap)continue;
    if(s.type==='strike'&&s.target==='all')best=Math.max(best,s.N*(s.mult||1)*(s.repeat||1)*(s.frenzyEnemies?1.25:1)*(s.spread?2:1));
    if(s.type==='healEngine'){const hurt=E.units.filter(u=>alive(u)&&u.hp<u.maxHp).length;best=Math.max(best,s.H*hurt);}
  }
  if(!next.length)return 1;
  return best>=Math.max(...next)?1:0;
}
function trial(state,firstMe,o1,o2,rules){
  const st=clone(state);
  const r=resolveRound(st,[{me:firstMe,opt:o1,first:true},{me:1-firstMe,opt:o2,first:false}],rules);
  return {st,r};
}
export function playRound(state,rules){
  const first=state.round%2===1?0:1; // 攻方(0)奇数轮先手
  const o1s=options(state,first,rules);
  // 先手：最大化“后手最佳应对下”的结果。后手看见后最大化自身。
  let best=null;
  for(const o1 of o1s){
    let worst=Infinity,reply=null;
    for(const o2 of options(state,1-first,rules,false,o1)){
      const {st,r}=trial(state,first,o1,o2,rules);const v=evalFor(st,first,r.winner);
      if(v<worst){worst=v;reply=o2;}
    }
    if(!best||worst>best.v)best={v:worst,o1,o2:reply};
  }
  // 后手在真实局面里重新择优（与 min 一致）。
  const {st,r}=trial(state,first,best.o1,best.o2,rules);
  return {state:st,winner:r.winner,log:r.log,acts:[best.o1.skill?.name||'待机',best.o2.skill?.name||'待机'],first};
}
export function battle(sideA,sideD,rules=DEFAULT_RULES,trace=false){
  let state={round:0,pendingWatchers:[],sides:[sideA,sideD].map(S=>({...S,units:S.units.map(u=>({...u}))}))};
  const history=[];
  for(let r=1;r<=rules.maxRounds;r++){
    state.round=r;
    for(const S of state.sides){S.ap+=10*r;
      for(const u of S.units)if(u.downRound!==null&&r>=u.downRound+2){u.downRound=null;u.hp=u.maxHp;u.guardRound=rules.reviveGuard?r:null;}}
    if(rules.reviveGuard)for(const S of state.sides)for(const u of S.units)if(u.guardRound===r&&!u.unyielding){u.unyielding=true;u.unySpent=false;u._tmpUny=true;}
    const res=playRound(state,rules);state=res.state;
    if(rules.reviveGuard)for(const S of state.sides)for(const u of S.units)if(u._tmpUny){u.unyielding=false;u._tmpUny=false;}
    if(trace)history.push({round:r,first:res.first===0?'攻':'守',acts:res.acts,hp:state.sides.map(S=>S.units.map(u=>alive(u)?u.hp:'×').join('/')),log:res.log});
    if(res.winner!==null)return {winner:res.winner,round:r,history};
  }
  const e=evalFor(state,0,null);
  return {winner:'timeout',round:rules.maxRounds,margin:e,history};
}
