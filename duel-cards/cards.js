export const PROFESSIONS={WR:'愤怒',GR:'贪婪',GL:'暴食',EN:'嫉妒',SL:'怠惰',LU:'色欲',PR:'傲慢'};
export const RULES=[
 ['higher','更高','回应数字比待结算数字大 → 成功；否则失败。'],
 ['parity','同奇偶','两个数字同为奇数或同为偶数 → 成功；否则失败。'],
 ['near','接近','两个数字相差不超过3 → 成功；否则失败。'],
 ['sum','跨过二十','两个数字之和大于20 → 成功；否则失败。'],
 ['lower','更低','回应数字比待结算数字小 → 成功；否则失败。']
].map(([id,name,text])=>({id,name,text}));
export const judge=(rule,p,r)=>({higher:r>p,parity:r%2===p%2,near:Math.abs(r-p)<=3,sum:p+r>20,lower:r<p})[rule]?'success':'failure';
const cards=[];
function main(id,name,s,f,run,cost={}){cards.push({id,name,kind:'main',profession:/^[A-Z]+/.exec(id)[0],success:s,failure:f,run,cost});}
const d=(n,t='enemy')=>({type:'damage',n,target:t}),h=(n,t='self')=>({type:'heal',n,target:t}),a=(n,t='self')=>({type:'armor',n,target:t}),draw=n=>({type:'draw',n}),drop=n=>({type:'discard',n});
main('N01','试探','对手受到6点伤害。','自己恢复6点生命。',()=>[[d(6)],[h(6)]]);
main('N02','护住要害','获得8点护甲。','恢复5点生命。',()=>[[a(8)],[h(5)]]);
main('N03','换一口气','对手受到8点伤害；自己失去3点生命。','对手受到3点伤害；获得5点护甲。',()=>[[d(8),{type:'loss',n:3}],[d(3),a(5)]]);
main('N04','整理思路','抽2张牌。','恢复7点生命。',()=>[[draw(2)],[h(7)]]);
main('N05','拆盾','移除对手8点护甲，再造成3点伤害。','获得6点护甲。',()=>[[{type:'removeArmor',n:8,target:'enemy'},d(3)],[a(6)]]);
main('N06','余力','获得2层储势：下一次主牌首段伤害+4。','恢复5点生命。',()=>[[{type:'status',name:'charge',n:2}],[h(5)]]);
main('N07','趁热','对手获得2层灼热，持续其下3张主牌结算。','移除自己的灼热，恢复3点生命。',()=>[[{type:'status',name:'burn',n:2,target:'enemy',duration:3}],[{type:'clear',name:'burn'},h(3)]]);
main('N08','收起锋芒','暂存自己选择的至多2张手牌，每张获得3甲；第二个后续回合归手。','抽2张牌。',()=>[[{type:'sleep',n:2,after:2,armor:3}],[draw(2)]]);
main('N09','直击','对手失去5点生命（通常绕过护甲）。','获得7点护甲。',()=>[[{type:'loss',n:5,target:'enemy'}],[a(7)]]);
main('N10','止血','恢复9点生命。','对手受到4点伤害。',()=>[[h(9)],[d(4)]]);
main('N11','破绽','对手获得2层暴露，持续其下2张主牌结算。','获得6点护甲。',()=>[[{type:'status',name:'exposed',n:2,target:'enemy',duration:2}],[a(6)]]);
main('N12','断药','对手获得2层禁疗，持续其下2张主牌结算。','移除自己的禁疗，恢复4点生命。',()=>[[{type:'status',name:'antiheal',n:2,target:'enemy',duration:2}],[{type:'clear',name:'antiheal'},h(4)]]);
main('N13','差距', '造成双方手牌差的绝对值+3点伤害，最多10。','抽1张牌，获得3甲。',({p,o})=>[[d(Math.min(10,3+Math.abs(p.hand.length-o.hand.length)))],[draw(1),a(3)]]);
main('N14','伤者','对生命更高者造成8点伤害；相等则对敌。','治疗生命更低者8点；相等则自己。',({p,o})=>[[d(8,p.life>o.life?'self':'enemy')],[h(8,p.life<=o.life?'self':'enemy')]]);
main('N15','三连击','连续造成三次2点伤害。','连续恢复三次2点生命。',()=>[[d(2),d(2),d(2)],[h(2),h(2),h(2)]]);
main('N16','轻装','手牌比对手少时造成9伤，否则4伤。','手牌比对手多时恢复9生命，否则4。',({p,o})=>[[d(p.hand.length<o.hand.length?9:4)],[h(p.hand.length>o.hand.length?9:4)]]);
main('N17','熔甲','获得8点护甲。','移除全部护甲，恢复等量生命，最多10。',({p})=>[[a(8)],[{type:'removeArmor',n:p.armor},h(Math.min(10,p.armor))]]);
main('N18','叫醒','取回至多2张暂存牌。','移除对手4点护甲，恢复3生命。',()=>[[{type:'wake',n:2}],[{type:'removeArmor',n:4,target:'enemy'},h(3)]]);
main('N19','拒绝','对手弃2张自己选择的手牌。','自己恢复4生命，对手抽1张。',()=>[[{type:'discard',n:2,target:'enemy'}],[h(4),{type:'draw',n:1,target:'enemy'}]]);
main('N20','回收','从自己的弃牌区取回一张其他普通主牌。','获得5点护甲。',()=>[[{type:'recover',n:1}],[a(5)]]);
main('WR06','赌命','生命不高于20时造成12伤，否则5伤。','恢复8生命。',({p})=>[[d(p.life<=20?12:5)],[h(8)]]);
main('WR12','割掌找刃','失去2生命，抽2张；最近3完整回合自伤含本次至少6时抽3。','取回一张自己的愤怒普通主牌。',({recent})=>[[{type:'loss',n:2},draw(recent+2>=6?3:2)],[{type:'recover',n:1,profession:'WR'}]]);
main('WR45','疼痛账本','造成4伤；最近3完整回合每自伤3额外+1，最多+4。','恢复3生命；同样每自伤3额外+1，最多+4。',({recent})=>[[d(4+Math.min(4,Math.floor(recent/3)))],[h(3+Math.min(4,Math.floor(recent/3)))]]);
main('GL04','第一口','造成9点伤害。','获得8点护甲。',()=>[[d(9)],[a(8)]],{discard:1});
main('GL15','越吃越饿','造成4伤；本局每弃3张手牌额外+1，最多+4。','抽到6张手牌，最多抽3。',({p})=>[[d(4+Math.min(4,Math.floor(p.discarded/3)))],[draw(Math.min(3,Math.max(0,6-p.hand.length)))]]);
main('GL30','反刍','取回一张普通主牌；累计弃牌8张时取回两张不同名主牌。','恢复6生命。',({p})=>[[{type:'recover',n:p.discarded>=8?2:1,distinct:true}],[h(6)]]);
main('GR03','现金流','抽3张牌。','恢复4生命；本回合额外获取至少3张牌则恢复7。',({p})=>[[draw(3)],[h(p.acquired>=3?7:4)]]);
main('GR21','四方结算','造成11伤；材料每种此前未交割的名字+2，最多+6。','恢复8生命，取回本次仍在弃牌区的一张材料。',({combo})=>[[d(11+(combo.tradeBonus||0))],[h(8),{type:'recover',n:1,ids:combo.materials}]],{discard:3,trade:true});
main('GR35','仓库盘点','每张暂存牌使3点基础伤害+2，最多9。','取回至多2张暂存牌，每张获得3甲。',({p})=>[[d(3+Math.min(6,p.sleep.length*2))],[{type:'wake',n:2,armor:3}]]);
main('EN16','销赃','造成10伤。','恢复6生命，取走敌方弃牌区一张普通主牌。',()=>[[d(10)],[h(6),{type:'stealDiscard',n:1}]],{alienExile:1});
main('EN21','你的盾','对手失去其护甲一半的生命，最多8。','转移对手至多4甲给自己。',({o})=>[[{type:'loss',n:Math.min(8,Math.floor(o.armor/2)),target:'enemy'}],[{type:'stealArmor',n:4}]]);
main('EN50','学会了','造成4伤；本局打过至少两种异主牌时改8。','取回自己弃牌区一张异主普通主牌。',({p})=>[[d(p.usedAlien.length>=2?8:4)],[{type:'recover',n:1,alien:true}]]);
main('SL10','积压的怨气','造成3伤，每张暂存牌+1，最多8。','取回一张暂存牌，恢复5生命。',({p})=>[[d(3+Math.min(5,p.sleep.length))],[{type:'wake',n:1},h(5)]]);
main('SL23','叫醒拳','取回一张暂存牌，取到才造成6伤。','延后一张暂存牌一回合，延后才获得7甲。',()=>[[{type:'wake',n:1,damage:6}],[{type:'postpone',n:1,armor:7}]]);
main('SL50','睡醒算账','移除全部护甲，造成4加移除量的伤害，最多14。','恢复4生命；最近3完整回合至少3张暂存牌归手时恢复9。',({p,returned})=>[[{type:'removeArmor',n:p.armor},d(Math.min(14,4+p.armor))],[h(returned>=3?9:4)]]);
main('LU15','满座','造成对手手牌数量除以3向下取整的伤害，最多9。','双方各抽2张。',({o})=>[[d(Math.min(9,Math.floor(o.hand.length/3)))],[draw(2),{type:'draw',n:2,target:'enemy'}]]);
main('LU34','给出去以后','造成5伤；最近3完整回合交出至少2张牌则9。','恢复5生命；符合上述条件再回收一张普通主牌。',({given})=>[[d(given>=2?9:5)],[h(5),...(given>=2?[{type:'recover',n:1}]:[])]]);
main('LU43','赔礼','自己恢复10生命，对手恢复4。','自己获得8甲，对手获得3甲。',()=>[[h(10),h(4,'enemy')],[a(8),a(3,'enemy')]]);
main('PR08','面子比甲重','自己至少8甲时造成10伤，否则4伤。','移除至多4甲，每点恢复2生命。',({p})=>[[d(p.armor>=8?10:4)],[{type:'removeArmor',n:Math.min(4,p.armor)},h(Math.min(4,p.armor)*2)]]);
main('PR43','一锤定论','造成18点伤害。','造成8伤，恢复6生命。',()=>[[d(18)],[d(8),h(6)]],{discard:2});
main('PR48','收官陈词','敌方生命不高于20时造成11伤，否则5伤。','敌方手牌不多于5时自己获得8甲，否则敌方弃2张。',({o})=>[[d(o.life<=20?11:5)],o.hand.length<=5?[a(8)]:[{type:'discard',n:2,target:'enemy'}]]);
const supp=[['U01','翻倍','本牌伤害、治疗、护甲数值翻倍（不改变费用）。'],['U02','减半','本牌伤害、治疗、护甲减半向下取整。'],['U03','治疗铸甲','本牌所有治疗改为同目标护甲。'],['U04','熔甲疗伤','本牌所有获得护甲改为同目标治疗。'],['U05','逆转医术','本牌治疗与伤害互换，目标不变。'],['U06','分段','本牌每段普通伤害拆为两段，总数不变。']];
for(const [id,name,text]of supp)cards.push({id,name,text,kind:'support',profession:'U'});
// Only implemented, explicit effects appear in playable decks. Legacy 500-card prose is not parsed.
const fields={
 WR:[['伤口不会消失','所有治疗改为等量护甲。'],['血肉换铁','回合出牌前可支付至多6生命换等量护甲。'],['疼痛换选择','回合出牌前可支付4生命抽2张，傲慢不能主动使用。'],['满盾开刃','溢出护甲转为对敌伤害，每张主牌最多6。'],['把盾还给血','自己回合结束时，至多4甲转为实际需要的治疗。']],
 GR:[['挑选库存','额外抽牌时多看2张，选择原定数量，其余放牌库底。'],['货物暂存','额外抽到的牌可暂存至下回合，每张得2甲，每次抽牌最多6甲。'],['清仓保命','出牌前可将至多两张手牌放牌库底，每张得4甲。'],['借明天的牌','正常抽牌时可改抽3，之后两次正常抽牌跳过，欠抽未清不能再借。'],['库存抵押','每张敌方主牌首次伤到生命时，可弃一张手牌减少至多5点该伤害。']],
 GL:[['什么都能吃','出牌前可弃至多两张手牌，每张治疗4。'],['多挑两口','额外抽牌多抽2张，再弃2张手牌。'],['吃饱了再打','溢出治疗转为对敌伤害，每张主牌最多8。'],['旧牌下锅','出牌前可放逐弃牌区两张普通主牌，取回另一张普通主牌。'],['饱腹的代价','每回合第一批弃手牌时，可将其中一张暂存到下回合，替代弃置；这张不计弃牌量。']],
 EN:[['旧物交换','出牌前可交给对手一张普通主牌，取走其弃牌区一张普通主牌。'],['扔掉就归别人','每人每回合第一张弃手牌改为交给对手，不计实际弃牌；费用算已付。'],['薄盾分厚盾','每张主牌结算后，甲差超过6时，多甲者转移3甲给少甲者。'],['先救低处','每段治疗落在生命较低者；相等保持原目标。'],['借走这股劲','出牌前可付3甲，复制对手一个自己没有的状态，层数与期限不变。']],
 SL:[['明日再伤','伤害扣甲后，生命伤害记账，到受伤者下一次自己回合结束时扣除。'],['牌先睡','出牌前可暂存至多两张手牌，每张得3甲，第二个后续回合归手。'],['拆被叫醒','出牌前可每付3甲取回一张暂存牌，最多两张。'],['再睡一轮','暂存牌自然到期时，可整批延后一回合，每张治疗3；每张最多延后一次。'],['只拿眼前','正常抽牌时可放弃，改治疗5或获得5甲。']],
 LU:[['治疗有回礼','一方实际回血，另一方获得等量甲，每张主牌最多6甲。'],['满了就让给别人','溢出治疗或护甲转给另一方同类资源；二次溢出消失。'],['礼物先放一晚','从对手手里收到的牌公开暂存至下回合，满区则直接入手。'],['给你选择，给我时间','出牌前可让对手抽2张，自己治疗8。'],['多拿的人替挡','少手牌者受普通伤害，先用多手牌者至多3甲抵挡；每张主牌一次。']],
 PR:[['这一张留下','普通主牌结算后，可弃另一张普通主牌，收回刚结算的牌。'],['借来的盾','回合开始得5临时甲，回合末未消耗部分移除；可以支付费用。'],['先拆盾，再谈血','牌效果的失去生命也先扣甲，生命费用和疲劳除外。'],['拿牌挡一下','每张敌方主牌可弃一张手牌，挡住其中一段不超过8点的普通伤害。'],['不借助第二张','出牌时可亮出全部手牌且不搭辅牌，结算后回收一张不同名普通主牌。']]
};
for(const [profession,list]of Object.entries(fields))list.forEach(([name,text],i)=>cards.push({id:`${profession}-R${i+1}`,name,text,kind:'field',profession}));
export const CARDS=Object.fromEntries(cards.map(c=>[c.id,c]));
export const ALL_CARDS=cards;
export function defaultDeck(profession){
 const personal=cards.filter(c=>c.kind==='main'&&c.profession===profession).map(c=>c.id);
 const rules=[`${profession}-R1`,`${profession}-R2`,`${profession}-R4`];
 const supports=profession==='PR'?[]:['U01','U03'];
 const neutral=cards.filter(c=>c.profession==='N'&&!(profession==='PR'&&['N04','N08','N13','N18','N20'].includes(c.id))).slice(0,20-personal.length-rules.length-supports.length).map(c=>c.id);
 return [...personal,...neutral,...rules,...supports].map((id,index)=>({id,copies:index<15?2:1}));
}
