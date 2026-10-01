import {readFileSync,writeFileSync} from 'node:fs';
const words=readFileSync(new URL('./词库.tsv',import.meta.url),'utf8').trim().split(/\r?\n/).slice(1)
  .map(s=>{const [id,,,rarity]=s.split('\t');return {id,rarity};});
const pools=Object.fromEntries(['基础','进阶','奇术'].map(r=>[r,words.filter(w=>w.rarity===r).map(w=>w.id)]));
const basics=new Set(pools['基础']);
const templates=[['001','002','064','065','026','015','016'],['001','002','021','015','016'],['001','002','022','015','016'],['001','002','028','015','016']];
const attack=['001','002','015','016','027'];
const counters={全队急救:['003','004','014','016','027'],全队减伤:['005','014','016','027'],全队伤转疗:['010','008','002','003','004','014','016','027','038','039','062','020']};
let seed=0x7719c53a;
function random(){seed^=seed<<13;seed^=seed>>>17;seed^=seed<<5;return(seed>>>0)/4294967296;}
function pick(a){return a[Math.floor(random()*a.length)];}
function draw(){let n=random();return pick(pools[n<.55?'基础':n<.95?'进阶':'奇术']);}
function opening(){let s=new Set(pick(templates));while(s.size<12)s.add(pick(pools['基础']));return s;}
function bag(){let s;do{s=new Set();while(s.size<20)s.add(draw());}while([...s].filter(x=>basics.has(x)).length<10);return s;}
function count(h,b,r){return r.filter(x=>!h.has(x)&&b.has(x)).length;}
function ready(h,r){return r.every(x=>h.has(x));}
function defenderScore(h,b){return Math.max(...Object.values(counters).map(r=>count(h,b,r)/(r.filter(x=>!h.has(x)).length||1)));}
const trials=30000,rows=[];
for(const rounds of [1,2,3,4,6]){
 let ar=0,healing=0,mitigation=0,conversion=0,any=0;
 for(let t=0;t<trials;t++){
  let a=opening(),d=opening();
  for(let r=1;r<=rounds;r++){
   const left=bag(),right=bag();
   const firstAttack=r%2===1;
   const attackerLeft=firstAttack?count(a,left,attack)>=count(a,right,attack):!(defenderScore(d,left)>=defenderScore(d,right));
   for(const x of attackerLeft?left:right)a.add(x);
   for(const x of attackerLeft?right:left)d.add(x);
  }
  if(ready(a,attack)){
   ar++;
   const h=ready(d,counters.全队急救),m=ready(d,counters.全队减伤),c=ready(d,counters.全队伤转疗);
   healing+=+h;mitigation+=+m;conversion+=+c;any+=+(h||m||c);
  }
 }
 rows.push({rounds,attackReadyPct:+(100*ar/trials).toFixed(2),conditionedOnAttack:{allHealPct:ar?+(100*healing/ar).toFixed(2):null,allMitigationPct:ar?+(100*mitigation/ar).toFixed(2):null,allConversionPct:ar?+(100*conversion/ar).toFixed(2):null,anyWordRoutePct:ar?+(100*any/ar).toFixed(2):null},attackSamples:ar});
}
const result={seed:'0x7719c53a',trials,method:'12个随机基础词开局含一条合法基础攻击模板，后续每轮两袋各20词、基础55%进阶40%奇术5%、每袋至少10基础。进攻方追全部敌方伤害；防守方在全队治疗、全队减伤、全队伤转疗三条词路线中追最接近者。轮流先选。这里只算词是否持有，不算AP、构筑数字、能否在同刻救活，也不把“全队减伤”一律判为足以承受。',rows};
writeFileSync(new URL('./范围攻防抢词结果.json',import.meta.url),JSON.stringify(result,null,2)+'\n');
console.log(rows);
