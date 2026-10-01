import assert from 'node:assert/strict';
import {resolveTick,activationCost} from './参考结算器.mjs';

// Same 100-point boards as 见招拆招实战例.mjs. A adds a freely timed
// 分流: first 1 damage to the visible redirector, then 19 to every enemy.
// The direct filled total stays 20 and the activation fee stays 5.
const A=Object.fromEntries(Array.from({length:5},(_,i)=>[`A${i}`,{hp:i===0?76:1,maxHp:i===0?76:1,downAt:null}]));
const D=Object.fromEntries(Array.from({length:5},(_,i)=>[`D${i}`,{hp:i===0?95:1,maxHp:i===0?95:1,downAt:null}]));
const every=process.argv.includes('--every');
const ap={A:0,D:0},history=[];
function active(team){return Object.keys(team).filter(id=>team[id].hp>0);}
function revive(team,round){for(const c of Object.values(team))if(c.downAt!==null&&c.downAt+2<=round){c.hp=c.maxHp;c.downAt=null;}}
for(let round=1;round<=6;round++){
  revive(A,round);revive(D,round);ap.A+=10*round;ap.D+=10*round;
  const commands=[];
  if(A.A0.hp>0&&ap.A>=activationCost([20])){
    ap.A-=activationCost([20]);
    if(D.D0.hp>0)commands.push({kind:'damage',source:'A0',target:'D0',amount:1,order:1});
    for(const target of active(D))commands.push({kind:'damage',source:'A0',target,amount:19,order:2});
  }
  if(D.D0.hp>0&&commands.length&&ap.D>=activationCost([])){
    ap.D-=activationCost([]);
    commands.push({kind:'install',watcher:{id:`redirect-r${round}`,phase:'pending',owner:'D0',accepts:'damage',type:'redirect',to:'source',once:!every}});
  }
  let sweep=false;
  if(every&&round===6&&A.A0.hp===0&&D.D1.hp>0&&ap.D>=activationCost([1])){
    ap.D-=activationCost([1]);sweep=true;
    for(const target of active(A))commands.push({kind:'damage',source:'D1',target,amount:1,order:3});
  }
  const resolved=resolveTick({...A,...D},commands);
  for(const[id,c]of Object.entries(resolved.cards)){
    const original=(id.startsWith('A')?A:D)[id];
    if(original.hp>0&&c.hp===0)original.downAt=round;
    original.hp=c.hp;
  }
  history.push({round,casterHp:A.A0.hp,redirectorHp:D.D0.hp,sweep,attackersAlive:active(A).length,defendersAlive:active(D).length,
    redirectCount:resolved.trace.filter(x=>x.startsWith('redirect:')).length});
  if(active(A).length===0||active(D).length===0)break;
}
console.table(history);
assert.equal(history.length,6);
if(every){
  assert.equal(history.at(-1).sweep,true);
  assert.equal(history.at(-1).attackersAlive,0);
  assert.ok(history.at(-1).defendersAlive>0);
  console.log('再反拆招通过：加上「每次」后1点探针和19点全体伤害都改道，施法者休整时扫掉其余队友。');
}else{
  assert.equal(history.at(-1).redirectorHp,0);
  assert.equal(history.at(-1).defendersAlive,0);
  assert.ok(history.at(-1).attackersAlive>0);
  console.log('反拆招通过：1点探针耗去首次转移，随后19点全体伤害逐轮击倒守者。');
}
