import {ATTRIBUTES, KEYWORDS, STATUSES, OPERATIONS, SHAPES} from './catalog.js';

export const POS_NAMES = ['上','右','下','左','中'];
export const POS_IDS = ['u','r','d','l','c'];
const COORDS = [[0,-1],[1,0],[0,1],[-1,0],[0,0]];
const opMap = new Map(OPERATIONS.map(op => [op.id,op]));
const clamp = n => Math.max(-30,Math.min(30,Math.trunc(n)));
const sum = a => a.reduce((n,v) => n+v,0);
const mean = a => sum(a)/a.length;
const sorted = a => [...a].sort((a,b) => a-b);
const median = a => sorted(a)[Math.floor(a.length/2)];
const mod = (v,n) => ((v%n)+n)%n;
const gcd = (a,b) => { a=Math.abs(a); b=Math.abs(b); while(b) [a,b]=[b,a%b]; return a; };
const prime = n => { if(n<2) return false; for(let d=2;d*d<=n;d++) if(n%d===0) return false; return true; };
const result = () => ({events:[],notes:[]});
const active = (cell,id) => (cell.statuses[id]?.turns ?? 0)>0;
const has = (cell,id) => !active(cell,'muted') && cell.keywords.includes(id);
function targetsChecked(targets) {
  if(!Array.isArray(targets) || !targets.length || targets.some(i => !Number.isInteger(i)||i<0||i>4) || new Set(targets).size!==targets.length)
    throw new RangeError('目标必须是互不重复的0至4位置。');
  return [...targets];
}
export function makeBoard(values=[0,0,0,0,0]) {
  if(!Array.isArray(values)||values.length!==5||values.some(v=>!Number.isFinite(v))) throw new TypeError('需要五个有限数值。');
  return {cells:values.map(v=>({value:clamp(v),attribute:null,keywords:[],statuses:{},initial:clamp(v),previous:clamp(v),lastDelta:0})),turn:0};
}
export function cloneBoard(board) {
  return {...board,cells:board.cells.map(c=>({...c,keywords:[...c.keywords],statuses:Object.fromEntries(Object.entries(c.statuses).map(([id,s])=>[id,{...s}]))}))};
}
export function rng(seed=0) {
  // FNV-1a seed hashing, then a uint32 Mulberry32 stream. No ambient randomness.
  let state=2166136261;
  for(const ch of String(seed)) state=Math.imul(state^ch.charCodeAt(0),16777619)>>>0;
  return () => { state=(state+0x6D2B79F5)>>>0; let n=state;
    n=Math.imul(n^(n>>>15),n|1); n^=n+Math.imul(n^(n>>>7),n|61);
    return ((n^(n>>>14))>>>0)/4294967296;
  };
}
export function placements(shape) {
  if(shape==='fixed') return [];
  if(!Object.hasOwn(SHAPES,shape)) throw new RangeError(`未知形状：${shape}`);
  const found=[];
  for(let anchor=0;anchor<5;anchor++) for(let rotation=0;rotation<4;rotation++) {
    const targets=SHAPES[shape].map(([dx,dy])=>{
      for(let r=0;r<rotation;r++) [dx,dy]=[-dy,dx];
      const [x,y]=COORDS[anchor]; return COORDS.findIndex(([px,py])=>px===x+dx&&py===y+dy);
    });
    if(targets.every(i=>i!==-1)) found.push({anchor,rotation,targets});
  }
  return found;
}
export function getCardTargets(card,anchor=4,rotation=0) {
  if(card.kind==='operation' && opMap.get(card.operationId)?.fixedTargets) return [...opMap.get(card.operationId).fixedTargets];
  if(card.shape==='fixed') return card.targets ? targetsChecked(card.targets) : null;
  const found=placements(card.shape).find(p=>p.anchor===anchor&&p.rotation===rotation);
  return found ? [...found.targets] : null;
}

// One bounded write pipeline. Secondary writes use the same defenses but NEVER
// schedule more secondary writes, including echo/conductor/keyword triggers.
function write(board,index,requested,reason,out,secondary=false) {
  if(!Number.isFinite(requested)) throw new RangeError('数值写入必须有限。');
  const cell=board.cells[index], before=cell.value;
  if(requested===before) return;
  if(active(cell,'frozen') || (secondary && cell.attribute==='rooted')) {
    out.notes.push(`${POS_NAMES[index]}：${active(cell,'frozen')?'冻结':'拒绝附带'}阻止写入。`); return;
  }
  let delta=Math.trunc(requested)-before;
  if(active(cell,'reversed')) delta=-delta;
  if(active(cell,'boosted')) delta*=2;
  if(active(cell,'weakened')) delta=Math.trunc(delta/2);
  switch(cell.attribute) {
    case 'guard': delta=Math.max(0,delta); break;
    case 'growth': if(delta>0) delta++; break;
    case 'fragile': if(delta<0) delta--; break;
    case 'inverter': delta=-delta; break;
    case 'limited': delta=Math.max(-3,Math.min(3,delta)); break;
  }
  if(has(cell,'double-rise')&&delta>0) delta*=2;
  if(has(cell,'half-fall')&&delta<0) delta=Math.trunc(delta/2);
  let after=before+delta;
  if(cell.attribute==='small') after=Math.max(-9,Math.min(9,after));
  if(cell.attribute==='even') after=Math.trunc(after/2)*2;
  if(has(cell,'nonnegative')) after=Math.max(0,after);
  after=clamp(after);
  if(active(cell,'shield') && after<before) {
    delete cell.statuses.shield; out.notes.push(`${POS_NAMES[index]}：一次止降已消耗。`); return;
  }
  if(after===before) return;
  cell.previous=before; cell.lastDelta=after-before; cell.value=after;
  out.events.push({index,before,after,reason});
  if(secondary) return;
  const amount=after-before, direction=Math.sign(amount);
  const extra=(i,n,label)=>write(board,i,n,`${reason}；${label}`,out,true);
  if(cell.attribute==='echo') extra(index,cell.value+Math.trunc(amount/2),'半量追加');
  if(cell.attribute==='conductor') extra((index+1)%5,board.cells[(index+1)%5].value+direction,'顺位传导');
  if(has(cell,'rebound')&&cell.value===0) extra(index,cell.initial,'零值回初');
  if(has(cell,'ring-pulse')) for(let i=0;i<4;i++) if(i!==index) extra(i,board.cells[i].value+direction,'外圈同号');
  if(has(cell,'center-pulse')&&index!==4) extra(4,board.cells[4].value+direction,'中格同号');
  if(has(cell,'trail')) extra((index+1)%5,before,'顺位写旧值');
}

function unaryValue(id,x,c) {
  const n=Math.abs(x);
  switch(id) {
    case 'add_two': return x+2;
    case 'negate': return -x;
    case 'absolute': return n;
    case 'square': return x*x;
    case 'signed-root': return Math.sign(x)*Math.floor(Math.sqrt(n));
    case 'halve': return Math.trunc(x/2);
    case 'reciprocal': return x===0?0:Math.trunc(30/x);
    case 'mod-three': return mod(x,3);
    case 'decimal-digit': return n%10;
    case 'sign': return Math.sign(x);
    case 'zero': return 0;
    case 'complement-nine': return 9-x;
    case 'round-five': return Math.round(x/5)*5;
    case 'even-up': return Math.ceil(x/2)*2;
    case 'digit-sum': return sum([...String(n)].map(Number));
    case 'reverse-digits': return Math.sign(x)*Number([...String(n)].reverse().join(''));
    case 'triangle-ten': return Math.min(mod(x,20),20-mod(x,20));
    case 'factorial-digit': { let f=1; for(let i=2;i<=n%10;i++) f*=i; return f; }
    case 'fibonacci-digit': { let a=0,b=1; for(let i=0;i<n%10;i++) [a,b]=[b,a+b]; return a; }
    case 'next-prime': { let p=Math.max(2,x+1); while(!prime(p)) p++; return p; }
    case 'bit-reverse': return parseInt((n&31).toString(2).padStart(5,'0').split('').reverse().join(''),2);
    case 'bit-count': return n.toString(2).split('1').length-1;
    case 'gray-code': return n^(n>>>1);
    case 'collatz': return x%2===0?x/2:3*x+1;
    case 'power-floor': return n===0?0:2**Math.floor(Math.log2(n));
    case 'log-two': return n===0?0:Math.floor(Math.log2(n));
    case 'divisor-count': { let count=0; for(let i=1;i<=n;i++) if(n%i===0) count++; return count; }
    case 'totient': { let count=0; for(let i=1;i<=n;i++) if(gcd(i,n)===1) count++; return count; }
    case 'proper-divisor-sum': { let total=0; for(let i=1;i<n;i++) if(n%i===0) total+=i; return total; }
    case 'digital-root': return n===0?0:1+(n-1)%9;
    case 'triangular': return n*(n+1)/2;
    case 'bit-complement': return (~n)&31;
    case 'restore-initial': return c.initial;
    case 'restore-previous': return c.previous;
    case 'repeat-delta': return x+c.lastDelta;
    case 'delta-magnitude': return Math.abs(c.lastDelta);
    case 'initial-gap': return Math.abs(x-c.initial);
    case 'initial-midpoint': return Math.trunc((x+c.initial)/2);
    case 'initial-gcd': return gcd(x,c.initial);
    case 'initial-xor': return n^Math.abs(c.initial);
    default: throw new RangeError(`未实现的单格操作：${id}`);
  }
}
function aggregateValue(id,x,i,v) {
  const unique=sorted([...new Set(v)]), avg=mean(v);
  switch(id) {
    case 'board-sum': return sum(v);
    case 'board-mean': return Math.trunc(avg);
    case 'board-median': return median(v);
    case 'board-min': return Math.min(...v);
    case 'board-max': return Math.max(...v);
    case 'board-range': return Math.max(...v)-Math.min(...v);
    case 'board-mode': return unique.reduce((best,n)=>v.filter(x=>x===n).length>v.filter(x=>x===best).length?n:best,unique[0]);
    case 'distinct-count': return unique.length;
    case 'positive-count': return v.filter(x=>x>0).length;
    case 'sign-balance': return sum(v.map(Math.sign));
    case 'absolute-sum': return sum(v.map(Math.abs));
    case 'root-mean-square': return Math.floor(Math.sqrt(mean(v.map(x=>x*x))));
    case 'mean-deviation': return Math.trunc(x-avg);
    case 'dense-rank': return unique.indexOf(x)+1;
    case 'nearest-gap': return Math.min(...v.filter((_,j)=>j!==i).map(n=>Math.abs(n-x)));
    case 'center-distance': return Math.abs(x-v[4]);
    case 'board-gcd': return v.reduce(gcd,0);
    case 'board-product': return v.reduce((a,b)=>a*b,1);
    case 'missing-nonnegative': { let n=0; while(v.includes(n)) n++; return n; }
    case 'frequency': return v.filter(n=>n===x).length;
    case 'other-sum': return sum(v)-x;
    case 'greater-sum': return sum(v.filter(n=>n>x));
    case 'median-distance': return Math.abs(x-median(v));
    case 'pair-distance-sum': return sum(v.map(n=>Math.abs(n-x)));
    case 'board-variance': return Math.floor(mean(v.map(n=>(n-avg)**2))+1e-10);
    default: throw new RangeError(`未实现的全盘读取操作：${id}`);
  }
}
function fixedValues(id,v) {
  const out=[...v], s=sorted(v);
  const ring=fn=>{ for(let i=0;i<4;i++) out[i]=fn(v[i],i,v[(i+2)%4],v[(i+1)%4],v[(i+3)%4]); return out; };
  switch(id) {
    case 'rotate-ring': return ring((x,i)=>v[(i+3)%4]);
    case 'swap-center-max': { const i=v.indexOf(Math.max(...v)); [out[i],out[4]]=[out[4],out[i]]; return out; }
    case 'sort-cross': return s;
    case 'reverse-rank': return v.map(x=>s[4-s.indexOf(x)]);
    case 'center-copy': return ring(()=>v[4]);
    case 'ring-mean-center': out[4]=Math.trunc(mean(v.slice(0,4))); return out;
    case 'swap_ud': [out[0],out[2]]=[out[2],out[0]]; return out;
    case 'opposite-sum': return ring((x,i,opp)=>x+opp);
    case 'opposite-difference': return ring((x,i,opp)=>x-opp);
    case 'neighbor-sum': return ring((x,i,opp,next,prev)=>next+prev);
    case 'ring-gradient': return ring((x,i,opp,next,prev)=>next-prev);
    case 'laplacian': return ring((x,i,opp,next,prev)=>next+prev-2*x);
    case 'axis-gradient': out[4]=v[0]-v[2]+v[1]-v[3]; return out;
    case 'swap_rc': [out[1],out[4]]=[out[4],out[1]]; return out;
    case 'radial-add': return ring(x=>x+v[4]);
    case 'balance-extremes': { const lo=v.indexOf(s[0]), hi=v.indexOf(s[4]); if(lo!==hi) {out[lo]++;out[hi]--;} return out; }
    case 'equalize-total': { const total=sum(v), q=Math.floor(total/5), r=mod(total,5); return v.map((_,i)=>q+(i<r?1:0)); }
    case 'prefix-sum': return v.map((_,i)=>sum(v.slice(0,i+1)));
    case 'suffix-max': return v.map((_,i)=>Math.max(...v.slice(i)));
    case 'running-mean': return v.map((_,i)=>Math.trunc(mean(v.slice(0,i+1))));
    case 'first-difference': return v.map((x,i)=>i===0?x:x-v[i-1]);
    case 'opposite-product': return ring((x,i,opp)=>x*opp);
    case 'opposite-gcd': return ring((x,i,opp)=>gcd(x,opp));
    case 'opposite-lcm': return ring((x,i,opp)=>x===0||opp===0?0:Math.abs(x*opp)/gcd(x,opp));
    case 'soft-threshold': return ring(x=>Math.sign(x)*Math.max(0,Math.abs(x)-Math.abs(v[4])));
    case 'winsorize': return v.map(x=>Math.max(s[1],Math.min(s[3],x)));
    case 'normalize-range': return v.map(x=>s[4]===s[0]?0:Math.floor(10*(x-s[0])/(s[4]-s[0])));
    case 'center-reservoir': for(let i=0;i<4;i++) {out[i]-=Math.sign(v[i]);out[4]+=Math.sign(v[i]);} return out;
    case 'positive-pool': for(let i=0;i<4;i++) if(v[i]>0) {out[4]+=v[i];out[i]=0;} return out;
    case 'bubble-pass': for(let i=0;i<4;i++) if(out[i]>out[i+1]) [out[i],out[i+1]]=[out[i+1],out[i]]; return out;
    case 'alternating-sum': out[4]=v[0]-v[1]+v[2]-v[3]+v[4]; return out;
    case 'orthogonal-projection': out[0]=out[2]=Math.trunc((v[0]+v[2])/2); out[1]=out[3]=Math.trunc((v[1]+v[3])/2); return out;
    case 'median-filter': return ring((x,i,opp,next,prev)=>median([x,next,prev]));
    case 'difference-of-products': out[4]=v[0]*v[2]-v[1]*v[3]; return out;
    case 'center-split': for(let i=0;i<4;i++) out[i]+=Math.trunc(v[4]/4); out[4]=v[4]%4; return out;
    default: throw new RangeError(`未实现的固定操作：${id}`);
  }
}
export function applyOperation(board,operationId,targets) {
  const op=opMap.get(operationId);
  if(!op) throw new RangeError(`未知操作：${operationId}`);
  const indices=op.fixedTargets ? [...op.fixedTargets] : targetsChecked(targets);
  const snapshot=cloneBoard(board), v=snapshot.cells.map(c=>c.value), out=result();
  const proposed=op.category==='fixed' ? fixedValues(op.instruction,v) : null;
  // Read operands once; commit in ascending board order. Past cards are never
  // reevaluated. A trigger completes before the next primary write.
  for(const i of [...indices].sort((a,b)=>a-b)) {
    const next=proposed ? proposed[i] : op.category==='unary' ? unaryValue(op.instruction,v[i],snapshot.cells[i]) : aggregateValue(op.instruction,v[i],i,v);
    // An unchanged proposal is not a write and must not undo a preceding
    // trigger that happened to reach this cell during the same operation.
    if(next!==v[i]) write(board,i,next,op.name,out);
  }
  return out;
}
export function install(board,category,id,targets) {
  const list={attribute:ATTRIBUTES,keyword:KEYWORDS,status:STATUSES}[category];
  const effect=list?.find(e=>e.id===id);
  if(!effect) throw new RangeError(`未知授予：${category}/${id}`);
  const indices=targetsChecked(targets), out=result();
  for(const i of indices) {
    const c=board.cells[i];
    if(category==='attribute') c.attribute=id;
    if(category==='keyword'&&!c.keywords.includes(id)) c.keywords.push(id);
    if(category==='status') {
      if(c.keywords.includes('status-proof')) {out.notes.push(`${POS_NAMES[i]}：拒收状态。`);continue;}
      c.statuses[id]={turns:effect.turns};
    }
    out.notes.push(`${POS_NAMES[i]}获得${effect.name}。`);
  }
  return out;
}
export function tick(board) {
  const out=result();
  for(let i=0;i<5;i++) {
    const c=board.cells[i];
    if(has(c,'sprout')) write(board,i,c.value+1,'每回合加一',out);
    if(has(c,'wither')) write(board,i,c.value-1,'每回合减一',out);
    if(active(c,'burning')) write(board,i,c.value-2,'每回合减二',out);
    if(active(c,'healing')) write(board,i,c.value+2,'每回合加二',out);
    if(c.statuses.charge?.turns===1) write(board,i,c.value+5,'到期加五',out);
    if(c.statuses.doom?.turns===1) write(board,i,0,'到期归零',out);
  }
  // All statuses remain active through the full tick, then expire together.
  for(const c of board.cells) for(const [id,s] of Object.entries(c.statuses)) if(--s.turns<=0) delete c.statuses[id];
  board.turn++; return out;
}
export function executeCard(board,card,targets) {
  if(card.kind==='operation') {
    if(!opMap.has(card.operationId)) throw new RangeError('未知操作卡。');
    if(opMap.get(card.operationId).fixedTargets) return applyOperation(board,card.operationId);
  }
  const indices=targetsChecked(targets ?? (card.shape==='fixed'?card.targets:null));
  if(card.shape!=='fixed') {
    const key=[...indices].sort().join(',');
    if(!placements(card.shape).some(p=>[...p.targets].sort().join(',')===key)) throw new RangeError('形状放置不合法，不允许裁切。');
  }
  return card.kind==='operation' ? applyOperation(board,card.operationId,indices) : install(board,card.kind,card.effectId,indices);
}
export function preview(board,card,targets) {
  const copy=cloneBoard(board); return {board:copy,result:executeCard(copy,card,targets)};
}
