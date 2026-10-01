import test from 'node:test';
import assert from 'node:assert/strict';
import {resolveTick,activationCost,mitigationDamage,splitTotal,validateWordInstances} from './参考结算器.mjs';

const card=(hp,extra={})=>({hp,maxHp:hp,...extra});
test('同刻治疗抵消伤害，但一滴治疗不能抹掉过量伤害',()=>{
  const cards={a:card(10),b:card(10)};
  const hit=n=>resolveTick(cards,[{kind:'damage',source:'b',target:'a',amount:30},{kind:'heal',source:'a',target:'a',amount:n}]).cards.a.hp;
  assert.equal(hit(1),0);assert.equal(hit(25),5);assert.equal(hit(30),10);
});
test('固定与比例减伤调整，单段与多段确有不同收益',()=>{
  assert.equal(mitigationDamage(30,20,0),20);
  assert.equal(mitigationDamage(30,0,20),15);
  assert.equal(mitigationDamage(5,20,0),0);
  assert.equal(mitigationDamage(5,0,20),3);
  assert.equal(mitigationDamage(20,10,10),12);
  assert.throws(()=>mitigationDamage(20,11,10));
});
test('守护者安装后可同刻改写、改道；移除先于伤害',()=>{
  const cards={a:card(10),b:card(10)};
  const convert={id:'c',phase:'pending',owner:'a',accepts:'damage',type:'convert',toKind:'heal',once:true};
  const hit={kind:'damage',source:'b',target:'a',amount:8};
  assert.equal(resolveTick(cards,[{kind:'install',watcher:convert},hit]).cards.a.hp,10);
  assert.equal(resolveTick(cards,[{kind:'install',watcher:convert},{kind:'remove',watcherId:'c'},hit]).cards.a.hp,2);
  const redirect={id:'r',phase:'pending',owner:'a',accepts:'damage',type:'redirect',to:'source',once:true};
  const moved=resolveTick(cards,[{kind:'install',watcher:redirect},hit]);
  assert.equal(moved.cards.a.hp,10);assert.equal(moved.cards.b.hp,2);
});
test('范围原数值分别生效，全部转移会形成反噬',()=>{
  const cards={source:card(76),...Object.fromEntries('abcde'.split('').map(x=>[x,card(20)]))};
  const commands='abcde'.split('').map((target,order)=>({kind:'damage',source:'source',target,amount:20,order}));
  const redirects='abcde'.split('').map(owner=>({id:`r-${owner}`,phase:'pending',owner,accepts:'damage',type:'redirect',to:'source',once:true}));
  const normal=resolveTick(cards,commands);
  assert.deepEqual('abcde'.split('').map(id=>normal.cards[id].hp),[0,0,0,0,0]);
  const reflected=resolveTick(cards,commands,redirects);
  assert.equal(reflected.cards.source.hp,0);
  assert.deepEqual('abcde'.split('').map(id=>reflected.cards[id].hp),[20,20,20,20,20]);
});
test('第一次转移只移走第一段，第二段照常命中',()=>{
  const cards={a:card(30),b:card(30)};
  const w={id:'r',phase:'pending',owner:'a',accepts:'damage',type:'redirect',to:'source',once:true};
  const r=resolveTick(cards,[{kind:'damage',source:'b',target:'a',amount:5,order:1},{kind:'damage',source:'b',target:'a',amount:20,order:2}], [w]);
  assert.equal(r.cards.a.hp,10);assert.equal(r.cards.b.hp,25);
  const every=resolveTick(cards,[{kind:'damage',source:'b',target:'a',amount:5,order:1},{kind:'damage',source:'b',target:'a',amount:20,order:2}],
    [{...w,id:'r-every',once:false}]);
  assert.equal(every.cards.a.hp,30);assert.equal(every.cards.b.hp,5);
});
test('两人互相回敬同一因果链会终止，原始数值可惩罚过量攻击',()=>{
  const reflect=owner=>({id:`f-${owner}`,phase:'actual-damage',owner,type:'reflect',value:'actual',once:false});
  const r=resolveTick({a:card(50),b:card(50)},[{kind:'damage',source:'b',target:'a',amount:20}],[reflect('a'),reflect('b')]);
  assert.equal(r.cards.a.hp,10);assert.equal(r.cards.b.hp,30);
  assert.equal(r.trace.filter(x=>x.startsWith('reflect:')).length,2);
  const overkill=resolveTick({a:card(1),b:card(50)},[{kind:'damage',source:'b',target:'a',amount:100}],
    [{id:'orig',phase:'actual-damage',owner:'a',type:'reflect',value:'original',once:true}]);
  assert.equal(overkill.cards.a.hp,0);assert.equal(overkill.cards.b.hp,0);
});
test('状态免疫、首挡、不屈按公开结果生效',()=>{
  const r=resolveTick({a:card(5,{immunities:['狂振'],firstBlock:true,unyielding:true}),b:card(5)},
    [{kind:'status',source:'b',target:'a',status:'狂振'},
     {kind:'damage',source:'b',target:'a',amount:2,order:1},
     {kind:'damage',source:'b',target:'a',amount:9,order:2}]);
  assert.deepEqual(r.cards.a.statuses,[]);assert.equal(r.cards.a.hp,1);
  assert.equal(r.cards.a.firstBlockSpent,true);assert.equal(r.cards.a.unyieldingSpent,true);
});
test('启动费、分流、词实例边界',()=>{
  assert.equal(activationCost([]),5);assert.equal(activationCost([20]),25);
  assert.equal(activationCost([20,5]),30);assert.throws(()=>splitTotal(20,[5,16]));
  assert.deepEqual(splitTotal(20,[1,19]),[1,19]);
  assert.equal(validateWordInstances([{words:[{wordId:'027',instanceId:'bag1-1'}]},{words:[{wordId:'027',instanceId:'bag2-7'}]}]),true);
  assert.throws(()=>validateWordInstances([{words:[{wordId:'027',instanceId:'bag1-1'}]},{words:[{wordId:'027',instanceId:'bag1-1'}]}]));
});
test('随机数值不越界：净伤、治疗、减伤、重复转移的结果有限',()=>{
  let s=0x4d98c0de;
  function rand(){s^=s<<13;s^=s>>>17;s^=s<<5;return s>>>0;}
  for(let i=0;i<10000;i++){
    const hp=1+rand()%100,damage=rand()%201,heal=rand()%201;
    const fixed=rand()%21,percent=rand()%(21-fixed);
    const reduced=mitigationDamage(damage,fixed,percent);
    assert.ok(reduced>=0&&reduced<=damage);
    const out=resolveTick({a:card(hp),b:card(100)},
      [{kind:'damage',source:'b',target:'a',amount:reduced},{kind:'heal',source:'a',target:'a',amount:heal}]);
    assert.equal(out.cards.a.hp,Math.min(hp,Math.max(0,hp-reduced+heal)));
  }
});
