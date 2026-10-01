import assert from 'node:assert/strict';

// Reference slice of the general in-flight effect rule. Each direct hit has a
// causal root; each installed redirect instance can fire once in that root.
function applyRedirects(event, redirects, legalTargets) {
  const used = new Set();
  const visited = [];
  for (;;) {
    const next = redirects.find((r) => r.owner === event.target && !used.has(r.id) && r.matches(event));
    if (!next) return {event,visited};
    used.add(next.id);
    const target = next.to(event);
    if (!legalTargets.has(target)) return {event,visited};
    visited.push({word:next.id,from:event.target,to:target});
    event = {...event,target};
  }
}
function settle(events, redirects, hp) {
  const legalTargets=new Set(Object.keys(hp));
  const out={...hp},paths=[];
  for(const event of events){
    const result=applyRedirects(event,redirects,legalTargets);
    paths.push(result.visited);
    const e=result.event;
    if(e.kind==='damage')out[e.target]=Math.max(0,out[e.target]-e.amount);
    else if(e.kind==='heal')out[e.target]=Math.min(e.maxHp,out[e.target]+e.amount);
  }
  return {hp:out,paths};
}
const five=Object.fromEntries(['a','b','c','d','e'].map(id=>[id,20]));
const hp={source:76,...five};
const blast=Object.keys(five).map(target=>({kind:'damage',source:'source',target,amount:20}));
const one=settle(blast,[{id:'redirect-a',owner:'a',matches:e=>e.kind==='damage',to:e=>e.source}],hp);
assert.equal(one.hp.a,20);
assert.equal(one.hp.source,56);
assert.deepEqual(['b','c','d','e'].map(id=>one.hp[id]),[0,0,0,0]);
const all=settle(blast,Object.keys(five).map(owner=>({id:`redirect-${owner}`,owner,matches:e=>e.kind==='damage',to:e=>e.source})),hp);
assert.equal(all.hp.source,0);
assert.deepEqual(Object.keys(five).map(id=>all.hp[id]),[20,20,20,20,20]);
const pingpong=settle([{kind:'damage',source:'source',target:'a',amount:7}],
  [{id:'a-to-source',owner:'a',matches:e=>e.kind==='damage',to:e=>e.source},
   {id:'source-to-a',owner:'source',matches:e=>e.kind==='damage',to:()=> 'a'}],hp);
assert.equal(pingpong.hp.a,13);
assert.equal(pingpong.paths[0].length,2);
assert.equal(pingpong.hp.source,76);
const invalid=settle([{kind:'damage',source:'source',target:'a',amount:7}],
  [{id:'bad',owner:'a',matches:()=>true,to:()=> 'absent'}],hp);
assert.equal(invalid.hp.a,13);
console.log('转移链4项核验通过：单体改道、五路反噬、相互改道有限终止、非法新目标不偷换原效果');
