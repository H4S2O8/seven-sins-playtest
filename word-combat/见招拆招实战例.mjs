import assert from 'node:assert/strict';
import {resolveTick,activationCost} from './参考结算器.mjs';

// Constructive six-round witness under the currently provisional rest rule:
// A invests 20 in a full-strength team blast, 76 HP in its caster, 1 HP in
// each other card. D invests 95 HP in a redirector, 1 in a later AoE attack,
// 1 HP in each other card. All five cards on each team total 100 points.
const A=Object.fromEntries(Array.from({length:5},(_,i)=>[`A${i}`,{hp:i===0?76:1,maxHp:i===0?76:1,downAt:null}]));
const D=Object.fromEntries(Array.from({length:5},(_,i)=>[`D${i}`,{hp:i===0?95:1,maxHp:i===0?95:1,downAt:null}]));
assert.equal(Object.values(A).reduce((n,c)=>n+c.maxHp,0)+20,100);
assert.equal(Object.values(D).reduce((n,c)=>n+c.maxHp,0)+1,100);
const ap={A:0,D:0},history=[];
function active(team){return Object.keys(team).filter(id=>team[id].hp>0);}
function revive(team,round){for(const c of Object.values(team))if(c.downAt!==null&&c.downAt+2<=round){c.hp=c.maxHp;c.downAt=null;}}
for(let round=1;round<=6;round++){
  revive(A,round);revive(D,round);ap.A+=10*round;ap.D+=10*round;
  const aTargets=active(D),dTargets=active(A),commands=[];
  const canBlast=A.A0.hp>0&&ap.A>=activationCost([20]);
  if(canBlast){ap.A-=activationCost([20]);for(const target of aTargets)commands.push({kind:'damage',source:'A0',target,amount:20});}
  const canRedirect=round<=5&&D.D0.hp>0&&canBlast&&ap.D>=activationCost([]);
  if(canRedirect){ap.D-=activationCost([]);commands.push({kind:'install',watcher:{id:`redirect-r${round}`,phase:'pending',owner:'D0',accepts:'damage',type:'redirect',to:'source',once:true}});}
  const canSweep=round===6&&D.D1.hp>0&&ap.D>=activationCost([1]);
  if(canSweep){ap.D-=activationCost([1]);for(const target of dTargets)commands.push({kind:'damage',source:'D1',target,amount:1});}
  const before={...A,...D};
  const resolved=resolveTick(before,commands);
  for(const[id,c]of Object.entries(resolved.cards)){
    const old=(id.startsWith('A')?A:D)[id];
    if(old.hp>0&&c.hp===0)old.downAt=round;
    old.hp=c.hp;
  }
  history.push({round,blast:canBlast,redirect:canRedirect,sweep:canSweep,casterHp:A.A0.hp,redirectorHp:D.D0.hp,attackersAlive:active(A).length,defendersAlive:active(D).length});
  if(active(A).length===0||active(D).length===0)break;
}
console.table(history);
assert.equal(history.length,6);
assert.equal(history.at(-1).sweep,true);
assert.equal(history.at(-1).attackersAlive,0);
assert.ok(history.at(-1).defendersAlive>0);
console.log('实战见证通过：单张通用转移反复迫使全体轰炸者自伤；其休整轮用1点全体攻击扫清其余队友。');
