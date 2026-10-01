import {readFileSync,writeFileSync} from 'node:fs';
const words=readFileSync(new URL('./词库.tsv',import.meta.url),'utf8').trim().split(/\r?\n/).slice(1).map(s=>{const [id,,,rarity]=s.split('\t');return{id,rarity};});
const pools=Object.fromEntries(['基础','进阶','奇术'].map(r=>[r,words.filter(w=>w.rarity===r).map(w=>w.id)]));
const basic=new Set(pools['基础']);
const frequent=new Set(['001','002','003','004','005','010','013','014','015','016','019','020','026','038','039','041','064','065','074','075']);
const slightlyCommon=new Set(['011','027','031','059','062','069','070']);
const weighted=Object.fromEntries(Object.entries(pools).map(([rarity,ids])=>[rarity,ids.flatMap(id=>Array(frequent.has(id)?3:slightlyCommon.has(id)?2:1).fill(id))]));
const starts=[['001','002','064','065','026','015','016'],['001','002','021','015','016'],['001','002','022','015','016'],['001','002','028','015','016']];
const responses=[['003','004','013'],['005','013']];
const attack=['001','002','015','016','027'];
const targeted=['001','002','064','065','026','015','016'];
const heal=['003','004','014','016','027'];
const mitigate=['005','014','016','027'];
const convert=['010','008','002','003','004','014','016','027','038','039','062','020'];
let seed=0x714da95c;
function rand(){seed^=seed<<13;seed^=seed>>>17;seed^=seed<<5;return(seed>>>0)/4294967296;}
function pick(a){return a[Math.floor(rand()*a.length)];}
function draw(){const n=rand();return pick(weighted[n<.55?'基础':n<.95?'进阶':'奇术']);}
function opening(){const s=[...pick(starts),...pick(responses)];while(s.length<12)s.push(pick(weighted['基础']));return s;}
function bag(){let s;do{s=Array.from({length:20},draw);}while(s.filter(x=>basic.has(x)).length<10);return s;}
function counts(xs){const m=new Map();for(const x of xs)m.set(x,(m.get(x)||0)+1);return m;}
function need(xs){return counts(xs);}
function missing(h,recipe){let n=0;for(const [k,v] of recipe)n+=Math.max(0,v-(h.get(k)||0));return n;}
function gain(h,b,recipe){const bh=counts(b);let n=0;for(const[k,v]of recipe)n+=Math.min(bh.get(k)||0,Math.max(0,v-(h.get(k)||0)));return n;}
function add(h,b){for(const x of b)h.set(x,(h.get(x)||0)+1);}
function union(a,b){return need([...a,...b]);}
const options=[need(heal),need(mitigate),need(convert)];
const optionsAndAttack=[union(heal,targeted),union(mitigate,targeted),union(convert,targeted)];
const trials=20000,rows=[];
for(const rounds of [2,4,6,8]){
 let nAttack=0,nOnly=0,nBoth=0,nCanStillAttack=0;
 for(let t=0;t<trials;t++){
  const a=counts(opening()),d=counts(opening());
  for(let r=1;r<=rounds;r++){
   const l=bag(),q=bag();
   const first=r%2===1;
   const asL=gain(a,l,need(attack)),asQ=gain(a,q,need(attack));
   const dsL=Math.max(...options.map(o=>gain(d,l,o))),dsQ=Math.max(...options.map(o=>gain(d,q,o)));
   const aL=first?asL>=asQ:!(dsL>=dsQ);
   add(a,aL?l:q);add(d,aL?q:l);
  }
  if(missing(a,need(attack))===0){
   nAttack++;
   const only=options.some(o=>missing(d,o)===0);
   const both=optionsAndAttack.some(o=>missing(d,o)===0);
   nOnly+=+only;nBoth+=+both;nCanStillAttack+=+(missing(d,need(targeted))===0);
  }
 }
 rows.push({rounds,attackerReadyPct:+(100*nAttack/trials).toFixed(2),attackSamples:nAttack,
  defenderAnyWordCounterPct:nAttack?+(100*nOnly/nAttack).toFixed(2):null,
  defenderCounterAndSeparateTargetedAttackPct:nAttack?+(100*nBoth/nAttack).toFixed(2):null,
  defenderTargetedAttackReadyPct:nAttack?+(100*nCanStillAttack/nAttack).toFixed(2):null});
}
const result={seed:'0x714da95c',trials,method:'20词袋允许重复，基础55%进阶40%奇术5%，每袋至少10基础。常用语法及基础效果相对权重3，选中进阶连接/移除词权重2，其余1；开局12基础词随机包含一条基础攻击和一条自身治疗或自身减伤的完整句，其余随机可重复。两条句使用的词实例互不共用。只审持词，不审AP、预算和战斗。',rows};
writeFileSync(new URL('./词实例并装结果-攻守起手.json',import.meta.url),JSON.stringify(result,null,2)+'\n');
console.log(rows);
