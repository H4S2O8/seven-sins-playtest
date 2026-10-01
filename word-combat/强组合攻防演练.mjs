// 强组合 × 反制 全配对演练：词袋可得率（每袋20词） + 构筑/AP/多轮对局的最大最小搜索。
// 用法：node 强组合攻防演练.mjs [trials=4000] [规则变体名]
import {readFileSync,writeFileSync} from 'node:fs';
import {makeSide,skillBudget,battle,DEFAULT_RULES} from './攻防演练引擎.mjs';

// ---------- 词组表达 ----------
const W=(...ids)=>ids.map(id=>[[id]]);
const E1=[['064','065','026','015','016'],['024','015','016'],['021','015','016'],['022','015','016'],['028','015','016'],['023','015','016']];
const F1=[['064','065','026','014','016'],['013'],['024','014','016']];
const EA=[['027','015','016'],['029','015','016']];
const FA=[['027','014','016'],['029','014','016']];
const BASIC=[...W('001','002'),E1];

// ---------- 强组合（攻方） ----------
// 每项：words(词组)、builds(参数网格→技能列表)。
const G=(a,b)=>a.flatMap(x=>b.map(y=>[x,y]));
const strike=(o)=>({type:'strike',...o});
const basicAtk=N=>strike({name:'基础单体',target:'single',N});
export const COMBOS=[
 {id:'A1',name:'全体N',words:[...W('001','002'),EA],grid:[10,20,30,40].map(N=>[strike({name:'全体',target:'all',N})])},
 {id:'A2',name:'双倍全体',words:[...W('001','002','033'),EA],grid:[10,15,20,30].map(N=>[strike({name:'双倍全体',target:'all',N,mult:2})])},
 {id:'A3',name:'重复全体',words:[...W('001','002','072'),EA],grid:[10,15,20,30].map(N=>[strike({name:'重复全体',target:'all',N,repeat:2})])},
 {id:'A4',name:'双倍单体斩杀',words:[...W('001','002','033'),E1],grid:[10,20,30,40].map(N=>[strike({name:'双倍单体',target:'single',N,mult:2})])},
 {id:'A5',name:'重复单体破首挡',words:[...W('001','002','072'),E1],grid:[10,20,30].map(N=>[strike({name:'重复单体',target:'single',N,repeat:2})])},
 {id:'A6',name:'复制伤害',words:[...W('001','002','012','025'),E1],grid:[10,20,30,40].map(N=>[strike({name:'复制单体',target:'single',N,copy:true})])},
 {id:'A7',name:'分流两段',words:[...W('001','002','069','063','025'),E1],grid:[20,30,40].map(N=>[strike({name:'分流',target:'single',N,split:[Math.ceil(N/2),Math.floor(N/2)]})])},
 {id:'A8',name:'治疗引爆全体',words:[...W('066','038','041','059','003','004','001','002','075'),FA,FA,EA],
  grid:G([10,20,30],[10,20]).map(([H,N])=>[{type:'healEngine',name:'治疗引爆',H},basicAtk(N)])},
 {id:'A9',name:'伤害扩散',words:[...W('001','002','066','038','039','059','001','002','074','025'),EA,EA],grid:[10,20,30].map(N=>[strike({name:'扩散全体',target:'all',N,spread:true})])},
 {id:'A10',name:'狂振全体',words:[...W('001','002','066','010','090'),EA,EA],grid:[10,20,30,40].map(N=>[strike({name:'狂振全体',target:'all',N,frenzyEnemies:true})])},
 {id:'A11',name:'全队改道堡垒',words:[...W('038','034','059','009','019'),FA,...BASIC],
  grid:[10,20,30].map(N=>[{type:'watch',name:'改道堡垒',wtype:'redirect',owners:'all',every:true},basicAtk(N)])},
 {id:'A12',name:'双倍回敬坦克',words:[...W('038','039','059','013','001','002','033','074','019'),...BASIC],
  grid:[10,20,30].map(N=>[{type:'watch',name:'双倍回敬',wtype:'reflect',owners:'self',every:true,mult:2},basicAtk(N)])},
 {id:'A13',name:'连杀全体',words:[...W('001','002','066','038','050','059','001','002'),EA,EA],
  grid:G([10,20,30],[5,10]).map(([N,X])=>[strike({name:'连杀全体',target:'all',N,chainDown:true,extraN:X})])},
 {id:'A14',name:'重复双倍全体',words:[...W('001','002','033','072'),EA],grid:[10,15,20].map(N=>[strike({name:'重复双倍全体',target:'all',N,mult:2,repeat:2})])},
 {id:'A15',name:'反射全队+输出',words:[...W('038','039','059','001','002','074','019'),FA,...BASIC],
  grid:[10,20,30].map(N=>[{type:'watch',name:'全队回敬',wtype:'reflect',owners:'all',every:true},basicAtk(N)])},
];


// ---------- 组合式生成：把可结算的增幅/连锁/时序部件做笛卡尔积 ----------
// 每个部件带自己的词组；生成后去掉语义重复（例如单体不接“全体扩散”式部件以外的非法搭配）。
const PARTS={
  target:{single:{words:[E1]},all:{words:[EA]}},
  mult:{1:{words:[]},2:{words:W('033')}},
  repeat:{1:{words:[]},2:{words:W('072')}},
  extra:{
    none:{words:[]},
    copy:{words:W('012','025'),only:'single'},
    split:{words:W('069','063','025'),only:'single'},
    spread:{words:[...W('066','038','039','059','001','002','074','025'),EA]},
    chainDown:{words:[...W('066','038','050','059','001','002'),EA]},
    frenzy:{words:[...W('066','010','090'),EA]},
    frenzySpread:{words:[...W('066','010','090','066','038','039','059','001','002','074','025'),EA,EA]},
    frenzyChain:{words:[...W('066','010','090','066','038','050','059','001','002'),EA,EA]},
  },
};
export function generateCombos(){
  const out=[];let n=0;
  for(const [tg,T] of Object.entries(PARTS.target))for(const [m,M] of Object.entries(PARTS.mult))for(const [rp,R] of Object.entries(PARTS.repeat))for(const [ex,X] of Object.entries(PARTS.extra)){
    if(X.only&&X.only!==tg)continue;
    if(ex==='split'&&rp==='2')continue; // 分流与重复同节点语义未定
    const words=[...W('001','002'),...T.words,...M.words,...R.words,...X.words];
    const Ns=[10,15,20,30,40].filter(N=>N*(+m)*(+rp)<=90&&N+((ex.includes('hain'))?10:0)<=60);
    const grid=Ns.flatMap(N=>(ex.includes('hain')?[5,10]:[0]).map(Xn=>[strike({name:`生成${tg}×${m}×${rp}+${ex}`,target:tg,N,mult:+m,repeat:+rp,
      copy:ex==='copy',split:ex==='split'?[Math.ceil(N/2),Math.floor(N/2)]:null,spread:ex.includes('pread'),chainDown:ex.includes('hain'),extraN:Xn||0,frenzyEnemies:ex.startsWith('frenzy')})]));
    out.push({id:`G${++n}`,name:`${tg==='all'?'全体':'单体'}${m==='2'?'·双倍':''}${rp==='2'?'·重复':''}${ex==='none'?'':'·'+ex}`,words,grid});
  }
  // 守中带攻：监听器(改道/回敬/转疗/引爆) × 作用域(自身/全队) × 次数(首次/每次) × 回敬倍率 + 基础输出
  for(const wt of ['redirect','reflect','reflect2'])for(const own of ['self','all'])for(const ev of [false,true]){
    const base=wt==='redirect'?W('038','034','009','019'):[...W('038','039','001','002','074','019'),...(wt==='reflect2'?W('033'):[])];
    const words=[...base,...(ev?W('059'):[]),...(own==='all'?[FA]:W('013')),...BASIC];
    out.push({id:`G${++n}`,name:`${own==='all'?'全队':'自身'}${ev?'每次':'首次'}${wt==='redirect'?'改道':wt==='reflect'?'回敬':'双倍回敬'}+输出`,words,
      grid:[10,20,30].map(N=>[{type:'watch',name:'监听',wtype:wt==='redirect'?'redirect':'reflect',owners:own,every:ev,mult:wt==='reflect2'?2:1},basicAtk(N)])});
  }
  for(const own of ['self','all'])for(const hitAll of [false,true]){
    out.push({id:`G${++n}`,name:`治疗引爆(${own==='all'?'全队治疗':'自疗'}→${hitAll?'全体':'单体'})`,
      words:[...W('066','038','041','059','003','004','001','002','075'),own==='all'?FA:[['013']],FA,hitAll?EA:E1],
      grid:G([10,20,30],[10,20]).map(([H,N])=>[{type:'healEngine',name:'治疗引爆',H,own,hitAll},basicAtk(N)])});
  }
  return out;
}

// ---------- 反制（守方，另有一条基础单体攻击） ----------
export const COUNTERS=[
 {id:'D0',name:'无反制',words:[],grid:[[]]},
 {id:'D1',name:'全队比例减伤',words:[...W('005'),FA],grid:[[{type:'mit',name:'全队减伤',target:'all',R:20}]]},
 {id:'D2',name:'单体减伤护核',words:[...W('005'),F1],grid:[[{type:'mit',name:'单体减伤',target:'single',R:20}]]},
 {id:'D3',name:'全队治疗',words:[...W('003','004'),FA],grid:[10,20,30].map(H=>[{type:'heal',name:'全队治疗',target:'all',H}])},
 {id:'D4',name:'起手自身改道(首次)',words:W('038','034','013','009','019'),grid:[[{type:'watch',name:'自身改道',wtype:'redirect',owners:'self',every:false}]],starter:2},
 {id:'D5',name:'全队每次改道',words:[...W('038','034','059','009','019'),FA],grid:[[{type:'watch',name:'全队改道',wtype:'redirect',owners:'all',every:true}]]},
 {id:'D6',name:'全队伤转疗',words:[...W('038','034','059','008','002','003','004'),FA],grid:[[{type:'watch',name:'全队转疗',wtype:'convert',owners:'all',every:true}]]},
 {id:'D7',name:'全队回敬',words:[...W('038','039','059','001','002','074','019'),FA],grid:[[{type:'watch',name:'全队回敬',wtype:'reflect',owners:'all',every:true,mult:1}]]},
 {id:'D8',name:'首挡+不屈',words:W('096','097'),grid:[[]],kw:{firstBlock:true,unyielding:true}},
 {id:'D9',name:'移除',words:[...W('011','031'),E1],grid:[[{type:'remove',name:'移除'}]]},
 {id:'D10',name:'免疫狂振',words:W('093'),grid:[[]],kw:{immuneFrenzy:true}},
 {id:'D11',name:'起手自身治疗',words:W('003','004','013'),grid:[10,20,30].map(H=>[{type:'heal',name:'自疗',target:'single',H}]),starter:0},
 {id:'D12',name:'起手自身减伤',words:W('005','013'),grid:[[{type:'mit',name:'自身减伤',target:'single',R:20}]],starter:1},
 {id:'D13',name:'回击',words:W('099'),grid:[[]],kw:{reflectOnce:true}},
];

// ---------- 对局搜索 ----------
const LAYOUTS=['even','tank','duo'];
const cloneSkills=l=>l.map(s=>({...s}));
function outcomeScore(res){ // 攻方视角
  if(res.winner===0)return 2+(10-res.round)*0.01;
  if(res.winner===1)return -2+(res.round)*0.01;
  if(res.winner==='draw-wipe')return 0;
  return Math.max(-0.9,Math.min(0.9,res.margin/300));
}
export function duel(combo,counter,rules){
  let best=null;
  for(const aSkills of combo.grid)for(const aL of LAYOUTS){
    const aUsed=aSkills.reduce((a,s)=>a+skillBudget(s),0);
    let worst=null;
    for(const dSkillsC of counter.grid)for(const dL of LAYOUTS)for(const Nb of [10,20]){
      const dSkills=[basicAtk(Nb),...cloneSkills(dSkillsC)];
      const dUsed=dSkills.reduce((a,s)=>a+skillBudget(s),0);
      const A=makeSide('攻',aL,aUsed,cloneSkills(aSkills)),D=makeSide('守',dL,dUsed,dSkills,counter.kw||{});
      if(!A||!D)continue;
      const res=battle(A,D,rules);const sc=outcomeScore(res);
      if(!worst||sc<worst.sc)worst={sc,res,dBuild:{layout:dL,skills:dSkills.map(s=>`${s.name}${s.N??s.H??s.R??''}`)}};
    }
    if(worst&&(!best||worst.sc>best.sc))best={...worst,aBuild:{layout:aL,skills:aSkills.map(s=>`${s.name}${s.N??s.H??''}${s.extraN?'+'+s.extraN:''}`)}};
  }
  return best;
}
export const verdict=sc=>sc<=-1?'守胜':sc>=1?'攻胜':'僵持';

// ---------- 词袋 ----------
const lex=readFileSync(new URL('./词库.tsv',import.meta.url),'utf8').trim().split(/\r?\n/).slice(1).map(s=>{const[id,,,r]=s.split('\t');return{id,r};});
const pools=Object.fromEntries(['基础','进阶','奇术'].map(r=>[r,lex.filter(w=>w.r===r).map(w=>w.id)]));
const common=new Set(['001','002','003','004','005','009','010','013','014','015','016','019','020','026','034','038','039','041','064','065','074','075']);
const medium=new Set(['011','027','031','059','062','069','070']);
const weighted=Object.fromEntries(Object.entries(pools).map(([r,ids])=>[r,ids.flatMap(id=>Array(common.has(id)?3:medium.has(id)?2:1).fill(id))]));
const basicSet=new Set(pools['基础']);
const STARTS=[['001','002','064','065','026','015','016'],['001','002','021','015','016'],['001','002','022','015','016'],['001','002','028','015','016']];
const RESP=[['003','004','013'],['005','013'],['038','034','013','009','019']];
let seed=0x5eed2026;
const rnd=()=>{seed^=seed<<13;seed^=seed>>>17;seed^=seed<<5;return(seed>>>0)/4294967296;};
const pick=a=>a[Math.floor(rnd()*a.length)];
const drawWord=()=>{const r=rnd();return pick(weighted[r<.55?'基础':r<.95?'进阶':'奇术']);};
function bag(){let a;do{a=Array.from({length:20},drawWord);}while(a.filter(x=>basicSet.has(x)).length<10);return a;}
function opening(){const resp=Math.floor(rnd()*3);const t=[...pick(STARTS),...RESP[resp]];while(t.length<12)t.push(pick(weighted['基础']));return{tokens:t,resp};}
// 缺词数：逐组选缺得最少的备选，消耗实例。
function missing(have,groups){
  const pool=new Map();for(const w of have)pool.set(w,(pool.get(w)||0)+1);
  const need=[];
  for(const alts of groups){
    let bestAlt=null,bestMiss=Infinity;
    for(const alt of alts){const p=new Map(pool);let m=0;for(const w of alt){if((p.get(w)||0)>0)p.set(w,p.get(w)-1);else m++;}if(m<bestMiss){bestMiss=m;bestAlt=alt;}}
    for(const w of bestAlt){if((pool.get(w)||0)>0)pool.set(w,pool.get(w)-1);else need.push(w);}
  }
  return need;
}
const bagScore=(b,need)=>{const c=new Map();for(const w of b)c.set(w,(c.get(w)||0)+1);let s=0;for(const w of need)if((c.get(w)||0)>0){s++;c.set(w,c.get(w)-1);}return s;};
// 返回每轮是否凑齐：攻方组合；守方反制+基础攻击（独立实例）。起手自带反制按 starter 判定。
export function draftPair(combo,counters,trials,rounds=6){
  const rows=[];
  for(let t=0;t<trials;t++){
    const a=opening(),d=opening();
    const dGoal=counters[0];
    const dGroups=c=>c.starter!==undefined&&d.resp===c.starter?[...BASIC]:[...BASIC,...c.words];
    const aReady=[],dReady=counters.map(()=>[]);
    for(let r=1;r<=rounds;r++){
      const L=bag(),R=bag(),aFirst=r%2===1;
      const aNeed=missing(a.tokens,combo.words),dNeed=missing(d.tokens,dGroups(dGoal));
      let aTakesL;
      if(aFirst)aTakesL=bagScore(L,aNeed)>=bagScore(R,aNeed);else aTakesL=!(bagScore(L,dNeed)>=bagScore(R,dNeed));
      a.tokens.push(...(aTakesL?L:R));d.tokens.push(...(aTakesL?R:L));
      aReady.push(missing(a.tokens,combo.words).length===0);
      counters.forEach((c,i)=>dReady[i].push(missing(d.tokens,dGroups(c)).length===0));
    }
    rows.push({aReady,dReady});
  }
  return rows;
}

// ---------- 主程序 ----------
const VARIANTS={
  基线:{},
  共享因果链:{aoeSharedRoot:true},
  复出保护:{reviveGuard:true},
  狂振10:{frenzy:1.10},
};
if(import.meta.url===`file:///${process.argv[1].replace(/\\/g,'/')}`||process.argv[1].endsWith('强组合攻防演练.mjs')){
  const trials=+(process.argv[2]||4000),vname=process.argv[3]||'基线';
  const rules={...DEFAULT_RULES,...VARIANTS[vname]};
  const t0=Date.now();
  const out={variant:vname,rules,trials,bag:'开局12基础词（随机攻击句+随机应对句）；每轮两袋各20词，基础55/进阶40/奇术5，每袋≥10基础，常用词3倍、中频2倍权重；轮流先选。',combos:[]};
  const LIST=process.argv[4]==='gen'?generateCombos():COMBOS;
  for(const combo of LIST){
    const pairs=[];
    for(const counter of COUNTERS){
      const b=duel(combo,counter,rules);
      pairs.push({counter:counter.id,name:counter.name,verdict:verdict(b.sc),score:+b.sc.toFixed(3),round:b.res.round,aBuild:b.aBuild,dBuild:b.dBuild});
    }
    const good=COUNTERS.filter((c,i)=>pairs[i].verdict==='守胜'&&c.id!=='D0');
    const soft=COUNTERS.filter((c,i)=>pairs[i].verdict==='僵持'&&c.id!=='D0');
    // 可得率：守方分别以每条有效反制为目标抽词，取最好者；同时统计“任一有效反制”。
    const avail={};
    for(const c of [...good,...soft]){
      const rows=draftPair(combo,[c],trials);
      const at=r=>{const ar=rows.filter(x=>x.aReady[r-1]);return{att:+(100*ar.length/trials).toFixed(1),defGivenAtt:ar.length?+(100*ar.filter(x=>x.dReady[0][r-1]).length/ar.length).toFixed(1):null};};
      avail[c.id]={r2:at(2),r4:at(4),r6:at(6)};
    }
    let any=null;
    if(good.length){
      const rows=draftPair(combo,good,trials);
      const at=r=>{const ar=rows.filter(x=>x.aReady[r-1]);return ar.length?+(100*ar.filter(x=>x.dReady.some(d=>d[r-1])).length/ar.length).toFixed(1):null;};
      any={r2:at(2),r4:at(4),r6:at(6)};
    }
    out.combos.push({id:combo.id,name:combo.name,vsNone:pairs[0].verdict,pairs,winningCounters:good.map(c=>c.id),holdingCounters:soft.map(c=>c.id),avail,anyWinningCounterGivenAtt:any});
    console.error(`${combo.id} ${combo.name}: 无反制=${pairs[0].verdict} 守胜=${good.map(c=>c.id).join(',')||'无'} 僵持=${soft.map(c=>c.id).join(',')||'无'} 任一守胜反制|攻齐 r2/r4/r6=${any?`${any.r2}/${any.r4}/${any.r6}`:'-'}  (${((Date.now()-t0)/1000).toFixed(0)}s)`);
  }
  writeFileSync(new URL(`./强组合攻防演练结果-${vname}.json`,import.meta.url),JSON.stringify(out,null,1)+'\n');
}
