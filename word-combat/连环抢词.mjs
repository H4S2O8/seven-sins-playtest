import {readFileSync,writeFileSync} from 'node:fs';
const words=readFileSync(new URL('./词库.tsv',import.meta.url),'utf8').trim().split(/\r?\n/).slice(1).map(s=>{const[id,,,rarity]=s.split('\t');return{id,rarity};});
const pools=Object.fromEntries(['基础','进阶','奇术'].map(r=>[r,words.filter(w=>w.rarity===r).map(w=>w.id)]));
const common=new Set(['001','002','003','004','005','009','010','013','014','015','016','019','020','026','034','038','039','041','064','065','074','075']);
const medium=new Set(['011','027','031','059','062','069','070']);
const weighted=Object.fromEntries(Object.entries(pools).map(([r,ids])=>[r,ids.flatMap(id=>Array(common.has(id)?3:medium.has(id)?2:1).fill(id))]));
const starts=[['001','002','064','065','026','015','016'],['001','002','021','015','016'],['001','002','022','015','016'],['001','002','028','015','016']];
const responses=[['003','004','013'],['005','013'],['038','034','013','009','019']];
const basics=new Set(pools['基础']);
let state=0x771c9e44;
function random(){state^=state<<13;state^=state>>>17;state^=state<<5;return(state>>>0)/4294967296;}
function pick(a){return a[Math.floor(random()*a.length)];}
function draw(){let r=random();return pick(weighted[r<.55?'基础':r<.95?'进阶':'奇术']);}
function opening(){let response=pick(responses),tokens=[...pick(starts),...response];while(tokens.length<12)tokens.push(pick(weighted['基础']));return{tokens,response:response===responses[2]?'redirect':'other'};}
function bag(){let a;do{a=Array.from({length:20},draw);}while(a.filter(x=>basics.has(x)).length<10);return a;}
function score(b,have,goals){return goals.reduce((sum,[id,w])=>sum+(!have.includes(id)&&b.includes(id)?w:0),0);}
const trials=30000;
let aoeR2=0,redirectAndAoeR2=0,splitR4=0,everyR4=0,bothR4=0,sweepR6=0,fullChain=0;
for(let t=0;t<trials;t++){
 const a=opening(),d=opening();let stage2=false,stage4=false;
 for(let r=1;r<=6;r++){
  const left=bag(),right=bag(),firstA=r%2===1;
  const aGoals=r<=2?[['027',3],['069',1]]:[['069',3],['064',1.5],['065',1.5],['026',1.5]];
  const dGoals=r<=4?[['059',2],['027',2]]:[['027',3],['059',1]];
  const aL=firstA?score(left,a.tokens,aGoals)>=score(right,a.tokens,aGoals):!(score(left,d.tokens,dGoals)>=score(right,d.tokens,dGoals));
  a.tokens.push(...(aL?left:right));d.tokens.push(...(aL?right:left));
  if(r===2){stage2=a.tokens.includes('027');aoeR2+=+stage2;redirectAndAoeR2+=+(stage2&&d.response==='redirect');}
  if(r===4&&stage2&&d.response==='redirect'){
   const split=['069','064','065','026'].every(id=>a.tokens.includes(id)),every=d.tokens.includes('059');
   splitR4+=+split;everyR4+=+every;bothR4+=+(split&&every);
   stage4=split&&every;
  }
  if(r===6&&stage2&&d.response==='redirect'){
   const sweep=d.tokens.includes('027');sweepR6+=+sweep;fullChain+=+(stage4&&sweep);
  }
 }
}
const pct=(n,d)=>d?+(100*n/d).toFixed(2):null;
const result={seed:'0x771c9e44',trials,method:'三种随机基础应对起手；后续两袋各20，允许重复，基础55%进阶40%奇术5%，常用词加权；进攻追全部、分流及能指定守者的目标词，防守若有转移起手则追每次与全部，轮流先选。只审取得词实例，不审技能安置、两次换词限制、AP或战斗。',
 aoeByRound2Pct:pct(aoeR2,trials),redirectStarterGivenAoePct:pct(redirectAndAoeR2,aoeR2),
 conditionedOnAoeAndRedirect:{samples:redirectAndAoeR2,splitByRound4Pct:pct(splitR4,redirectAndAoeR2),everyByRound4Pct:pct(everyR4,redirectAndAoeR2),bothByRound4Pct:pct(bothR4,redirectAndAoeR2),sweepByRound6Pct:pct(sweepR6,redirectAndAoeR2),allThreeUpgradesPct:pct(fullChain,redirectAndAoeR2)}};
writeFileSync(new URL('./连环抢词结果.json',import.meta.url),JSON.stringify(result,null,2)+'\n');
console.log(result);
