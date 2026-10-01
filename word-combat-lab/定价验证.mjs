// 词卡定价验证：操作费 = 5 + 填入数字 + 所用词卡价格之和；拆招总代价 ≥ 被拆技能操作费 × 80%。
// 目标：每个强组合在“最早能放出”的那一轮，守方凑齐至少一种拆招反打词的概率 ≈ 50% 以上，
// 且当轮付得起拆招。用法：node 定价验证.mjs [trials=2000]
import {writeFileSync} from 'node:fs';
import {COMBOS,COUNTERS,generateCombos,draftPair} from './强组合攻防演练.mjs';

// 词的作用分档：放大 / 效果与触发 / 语法。
const AMP=new Set(['027','029','033','072','012','059','069','070','066','071','073']);
const EFFECT=new Set(['001','002','003','005','006','007','008','009','010','011','034','038','039','040','041','042','043','044','045','046','047','048','049','050','051','052','090','091','092']);
const tier=id=>AMP.has(id)?'amp':EFFECT.has(id)?'eff':'gram';
// 取每组第一备选计价（与抽词时的实际备选价格相同档位，语法词为0不影响）。
const flat=groups=>groups.map(alts=>alts[0]).flat();
const price=(ids,p)=>ids.reduce((a,id)=>a+p[tier(id)],0);
const cumAP=r=>5*r*(r+1);

// 拆招反打集合：作用于或读取对方事件的整体，不看大小。
const COUNTER_IDS=['D4','D5','D6','D7','D9'];
const counters=COUNTER_IDS.map(id=>COUNTERS.find(c=>c.id===id));
const BASIC_ATTACK=['001','002','064','065','026','015','016'];

const PRICES=[];
for(const amp of [0,2,3,4,5,6,8])for(const eff of [0,1,2])PRICES.push({amp,eff,gram:0});

const trials=+(process.argv[2]||2000),ROUNDS=8,N=20; // 代表性填数：强组合主数字20
const combos=[...COMBOS,...generateCombos()];
const drafts=combos.map(c=>{
  // 守方以词数最少的拆招为抽词目标，但凑齐任意一种都算。
  const order=[...counters].sort((a,b)=>flat(a.words).length-flat(b.words).length);
  return draftPair(c,order,trials,ROUNDS).map(r=>({aReady:r.aReady,dReady:r.dReady,order}));
});

const report=[];
for(const p of PRICES){
  const rows=combos.map((c,i)=>{
    const numbers=c.grid[0][0].type==='healEngine'?20:N;
    const aCost=5+numbers+price(flat(c.words),p);
    let castRounds=[],hit=0,cast=0;
    for(const d of drafts[i]){
      const r=d.aReady.findIndex((ok,k)=>ok&&cumAP(k+1)>=aCost);
      if(r<0)continue;cast++;castRounds.push(r+1);
      const ok=d.order.some((ct,j)=>{
        const own=5+price(flat(ct.words),p);
        const need=Math.max(own,Math.ceil(0.8*aCost));
        return d.dReady[j][r]&&cumAP(r+1)>=need;
      });
      if(ok)hit++;
    }
    castRounds.sort((a,b)=>a-b);
    return {id:c.id,name:c.name,aCost,castPct:+(100*cast/trials).toFixed(1),
      medianRound:castRounds.length?castRounds[castRounds.length>>1]:null,
      counterAtCastPct:cast?+(100*hit/cast).toFixed(1):null};
  });
  const valid=rows.filter(r=>r.counterAtCastPct!==null);
  const pass=valid.filter(r=>r.counterAtCastPct>=50).length;
  const minRow=valid.reduce((a,b)=>b.counterAtCastPct<a.counterAtCastPct?b:a);
  const med=valid.map(r=>r.medianRound).sort((a,b)=>a-b);
  report.push({price:p,pass,total:valid.length,minCounterPct:minRow.counterAtCastPct,worst:minRow.name,
    medianCastRound:med[med.length>>1],rows});
  console.log(`放大${p.amp} 效果${p.eff}: 达标 ${pass}/${valid.length}  最差 ${minRow.counterAtCastPct}%(${minRow.name})  成型轮中位 ${med[med.length>>1]}`);
}
writeFileSync(new URL('./定价验证结果.json',import.meta.url),JSON.stringify({trials,rule:'操作费=5+数字+词价；拆招总代价≥被拆操作费×80%；成型轮=词齐且累计AP够',report},null,1)+'\n');
