// Small executable semantics for the four result interfaces. It consumes
// normalized events from a future word-tree editor; it is not a full editor.
export function mitigationDamage(amount, fixedPoints=0, percentPoints=0) {
  if (!Number.isInteger(amount) || amount < 0) throw new Error('damage must be a nonnegative integer');
  if (fixedPoints < 0 || percentPoints < 0 || fixedPoints+percentPoints > 20) throw new Error('mitigation points exceed 20');
  return Math.max(0,Math.ceil((amount-fixedPoints/2)*(1-percentPoints/40)));
}
export function activationCost(filledNumbers=[],fee=5) {
  if (filledNumbers.some(n=>!Number.isInteger(n)||n<0)) throw new Error('filled numbers must be nonnegative integers');
  return fee+filledNumbers.reduce((a,b)=>a+b,0);
}
export function splitTotal(total,parts) {
  if (!Number.isInteger(total)||total<0||parts.some(n=>!Number.isInteger(n)||n<0)||parts.reduce((a,b)=>a+b,0)!==total) throw new Error('split must conserve filled value');
  return parts;
}
export function validateWordInstances(skills) {
  const used=new Set();
  for(const skill of skills){
    for(const word of skill.words||[]){
      if(!word.instanceId||used.has(word.instanceId))throw new Error('one drawn word instance cannot occupy two nodes');
      used.add(word.instanceId);
    }
  }
  return true;
}
export function resolveTick(cards,commands,watchers=[],tick=0) {
  const ordered=[...commands].sort((a,b)=>(a.order??0)-(b.order??0)||String(a.id??'').localeCompare(String(b.id??'')));
  const out=Object.fromEntries(Object.entries(cards).map(([id,c])=>[id,{...c,statuses:[...(c.statuses||[])],immunities:[...(c.immunities||[])]}]));
  const active=watchers.map(w=>({...w}));
  const trace=[];
  // Install and remove are public control operations, always before numbers.
  for(const c of ordered.filter(c=>c.kind==='install')) active.push({...c.watcher});
  for(const c of ordered.filter(c=>c.kind==='remove')) {
    const i=active.findIndex(w=>w.id===c.watcherId);
    if(i>=0){active.splice(i,1);trace.push(`remove:${c.watcherId}`);}
  }
  const fresh=ordered.filter(c=>['damage','heal','status'].includes(c.kind)).map((c,i)=>({...c,root:c.root??`direct-${i}`}));
  const pending=[...fresh];
  const ledger=Object.fromEntries(Object.keys(out).map(id=>[id,{damage:0,heal:0,virtualHp:out[id].hp}]));
  const usedByRoot=new Map();
  let eventCount=0;
  while(pending.length){
    if(++eventCount>100000)throw new Error('causal chain did not terminate');
    let e=pending.shift();
    if(!out[e.target])throw new Error(`illegal target ${e.target}`);
    const used=usedByRoot.get(e.root)||new Set(); usedByRoot.set(e.root,used);
    // In-flight modifiers are public, in installation order. A redirect can
    // expose the same event to another target's modifier. Each instance once/root.
    for(;;){
      const w=active.find(w=>w.phase==='pending'&&w.owner===e.target&&w.accepts===e.kind&&!used.has(w.id)&&!w.spent);
      if(!w)break;
      used.add(w.id);if(w.once)w.spent=true;
      if(w.type==='redirect'){
        const target=w.to==='source'?e.source:w.to;
        if(!out[target]){trace.push(`invalid-redirect:${w.id}`);continue;}
        trace.push(`redirect:${w.id}:${e.target}->${target}`);
        e={...e,target};
      }else if(w.type==='convert'){
        trace.push(`convert:${w.id}:${e.kind}->${w.toKind}`);
        e={...e,kind:w.toKind};
      }else throw new Error(`unknown pending modifier ${w.type}`);
    }
    const target=out[e.target],book=ledger[e.target];
    if(e.kind==='status'){
      if(!target.immunities.includes(e.status)){target.statuses.push(e.status);trace.push(`status:${e.status}:${e.target}`);}
      else trace.push(`immune:${e.status}:${e.target}`);
      continue;
    }
    if(!Number.isInteger(e.amount)||e.amount<0)throw new Error('event amount must be nonnegative integer');
    if(e.kind==='heal'){
      book.heal+=e.amount;trace.push(`heal:${e.amount}:${e.target}`);continue;
    }
    let damage=mitigationDamage(e.amount,target.fixedPoints||0,target.percentPoints||0);
    if(damage>0&&target.firstBlock&&!target.firstBlockSpent){target.firstBlockSpent=true;damage=0;trace.push(`first-block:${e.target}`);}
    const actual=Math.max(0,Math.min(damage,book.virtualHp));
    book.damage+=damage;book.virtualHp=Math.max(0,book.virtualHp-damage);
    trace.push(`damage:${damage}:${e.target}:actual=${actual}`);
    if(actual>0){
      for(const w of active){
        if(w.phase!=='actual-damage'||w.owner!==e.target||used.has(w.id)||w.spent)continue;
        used.add(w.id);if(w.once)w.spent=true;
        if(w.type==='reflect'){
          const amount=w.value==='original'?e.amount:actual;
          pending.push({kind:'damage',source:e.target,target:e.source,amount,root:e.root});
          trace.push(`reflect:${w.id}:${amount}:${e.source}`);
        }
      }
    }
  }
  for(const [id,c] of Object.entries(out)){
    const b=ledger[id];
    c.hp=Math.max(0,Math.min(c.maxHp,c.hp-b.damage+b.heal));
    if(c.hp===0&&c.unyielding&&!c.unyieldingSpent){c.hp=1;c.unyieldingSpent=true;trace.push(`unyielding:${id}`);}
  }
  return {cards:out,watchers:active.filter(w=>!w.spent&&(!('until' in w)||w.until>tick)),trace,ledger};
}
