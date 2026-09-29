import type { Style } from "../src/ai/agents.js";
import { BASES, BY_ID, CHOICE_TEXT, FIELDS, type Card } from "../src/blood-fire/content.js";
import { BloodFireTable } from "../src/blood-fire/table.js";
import { BloodFireBot } from "../src/blood-fire/bot.js";
import { analyze, type Wheel } from "../src/blood-fire/analysis.js";
import type { Event as BattleEvent } from "../src/blood-fire/battle.js";
import { cardShell } from "./card-shell.js";

const esc=(s:string)=>s.replaceAll("&","&amp;").replaceAll("<","&lt;").replaceAll('"',"&quot;");
const POS=["前","中","后"];
const colors={blood:"#d04b52",fire:"#ef9a39",name:"#9d93db"};
export class BloodFireMode {
  private root:HTMLElement;
  private table:BloodFireTable|null=null;
  private style:Style="cautious";
  private bid=2;
  private selected=0;
  private preview=0;
  private playing=false;
  private delay=620;
  private error="";
  private enemyReady=false;
  private help=false;
  private wheel:Wheel="none";
  private analysisOpen=false;
  private inspectId:string|null=null;
  private botAgent:BloodFireBot|null=null;
  constructor(private hooks:{exit:()=>void}){
    this.root=document.createElement("section");this.root.id="blood-fire-mode";document.body.append(this.root);
    this.root.addEventListener("click",e=>this.click(e));
  }
  start(style:Style){this.style=style;const seed=Math.floor(Math.random()*2147483647);this.table=new BloodFireTable(seed);this.botAgent=new BloodFireBot(style,seed^0x51a7);this.bid=2;this.selected=0;this.preview=0;this.playing=false;this.enemyReady=false;this.help=false;this.wheel="none";this.analysisOpen=false;this.open();}
  private open(){this.root.classList.add("open");document.querySelector("#app")?.classList.add("numeric-hidden");this.draw();}
  private exit(){this.root.classList.remove("open");this.root.innerHTML="";document.querySelector("#app")?.classList.remove("numeric-hidden");this.table=null;this.hooks.exit();}
  private card(c:Card,opts:{selected?:boolean;down?:boolean;slot?:number;side?:number;hp?:number;shield?:number;click?:string}={}){
    const face=`<div class="art has-portrait"><img class="portrait" src="art/${c.art}.webp" alt="" draggable="false"><i class="varnish"></i></div><i class="orn"></i><span class="sin-tag">${c.faction==="blood"?"血":c.faction==="fire"?"火":"被遗忘之名"}</span><div class="plate"><span>${esc(c.name)}</span></div><div class="text"><span>${esc(c.basic)}</span><br><b>${esc(c.skill)}</b></div><div class="stats"><span title="数字越小，越早普通攻击；近战每有一名活着的队友站在前面，等待时间增加2拍">${c.kind==="melee"?"近战":"远程"} · 每 ${c.interval} 拍攻击一次</span><span class="stat atk" title="普通攻击伤害">${c.attack}</span><span class="stat hp" title="当前生命">${opts.hp??"?"}</span></div><i class="linen"></i><i class="sheen"></i><i class="gloss"></i>`;
    return cardShell({classes:`card person fr-1 foil bf-card ${opts.selected?"selected":""} ${opts.down?"down":""} ${opts.hp===0?"dead":""}`,attributes:`style="--sin:${colors[c.faction]}" ${opts.slot!==undefined?`data-unit="${opts.side}-${opts.slot}" data-n="${opts.slot}"`:""} ${opts.click?`data-act="${opts.click}" data-card="${c.id}" role="button" tabindex="0"`:""}`,front:face,back:`<div class="bf-card-back">被遗忘之名</div>`});
  }
  private planCopy(){return this.table!.plans[0].map(p=>({...p}));}
  private bot(){const t=this.table!,b=this.botAgent!;for(let guard=0;guard<6;guard++){
    if(t.phase==="draft"&&t.bids[1]===null)t.bid(1,b.draftBid(t));
    else if(t.phase==="arrange"&&t.auctionWinner===1)t.choose(1,b.pick(t));
    else if(t.phase==="field"&&t.bids[1]===null)t.bid(1,b.fieldBid(t));
    else if(t.phase==="field-choice"&&!t.planLocked[1]){if(t.noFieldWinner)t.lockPlan(1);else if(t.fieldWinner===1)t.fieldDecision(1,b.adopt(t));else t.lockPlan(1);}
    else if(t.phase==="bet"&&t.betTurn===1){const a=b.betAction(t);t.wager(1,a.kind,a.amount);}
    else break;
  }}
  private prepareBot(){const t=this.table!;if(t.plans[1].length!==3||this.enemyReady)return;this.enemyReady=true;t.configure(1,this.botAgent!.configure(t));}
  private click(e:Event){const el=(e.target as HTMLElement).closest<HTMLElement>("[data-act]");if(!el||!this.table||this.playing)return;const t=this.table,act=el.dataset.act!,n=Number(el.dataset.n??0);try{
    if(act==="exit"){this.exit();return;}if(act==="bid-down")this.bid=Math.max(0,this.bid-1);if(act==="bid-up")this.bid=Math.min(t.stacks[0],this.bid+1);
    if(act==="help")this.help=!this.help;
    if(act==="card-info")this.inspectId=el.dataset.card??null;
    if(act==="card-info-close")this.inspectId=null;
    if(act==="wheel")this.wheel=el.dataset.wheel as Wheel;
    if(act==="analysis-toggle")this.analysisOpen=!this.analysisOpen;
    if(act==="bid"){t.bid(0,this.bid);this.bot();this.bid=2;if(t.phase==="arrange")this.bot();}
    if(act==="pass"){t.bid(0,0);this.bot();this.bid=2;if(t.phase==="arrange")this.bot();}
    if(act==="field-adopt"){t.fieldDecision(0,true);this.bot();}
    if(act==="field-keep"){t.fieldDecision(0,false);this.bot();}
    if(act==="lock-plan"){t.lockPlan(0);this.bot();}
    if(act==="pick"){t.choose(0,n as 0|1);if(t.phase==="field")this.prepareBot();this.bot();}
    if(act==="select")this.selected=n;
    if(act==="swap"){const p=this.planCopy();[p[this.selected],p[n]]=[p[n],p[this.selected]];t.configure(0,p);this.selected=n;}
    if(act==="hp+"){const p=this.planCopy(),other=p.findIndex((v,i)=>i!==this.selected&&v.hp>4);if(p[this.selected].hp<12&&other>=0){p[this.selected].hp++;p[other].hp--;t.configure(0,p);}}
    if(act==="hp-"){const p=this.planCopy(),other=p.findIndex((v,i)=>i!==this.selected&&v.hp<12);if(p[this.selected].hp>4&&other>=0){p[this.selected].hp--;p[other].hp++;t.configure(0,p);}}
    if(act==="skill"){const p=this.planCopy();p[this.selected].enabled=!p[this.selected].enabled;t.configure(0,p);}
    if(act==="target"){const p=this.planCopy();p[this.selected].target=n as 0|1|2;t.configure(0,p);}
    if(act==="target2"){const p=this.planCopy();p[this.selected].target2=n as 0|1|2;t.configure(0,p);}
    if(act==="choice"){const p=this.planCopy();p[this.selected].choice=n as 0|1;t.configure(0,p);}
    if(act==="wager"){t.wager(0,el.dataset.kind as "check"|"call"|"raise"|"fold",el.dataset.kind==="raise"?this.bid:0);if(t.phase==="field"){this.enemyReady=false;this.prepareBot();}this.bot();if(t.phase==="over"&&t.result)this.play();}
    if(act==="replay"){this.preview=0;this.play();}
    if(act==="skip"){this.preview=t.result?.events.length??0;this.playing=false;this.draw();}
    if(act==="speed"){this.delay=this.delay===620?350:this.delay===350?100:620;}
    this.error="";this.draw();
  }catch(err){this.error=String(err);this.draw();}}
  private async play(){const t=this.table;if(!t?.result)return;this.playing=true;this.draw();const events=t.result.events;while(this.preview<events.length&&this.playing&&this.table===t){const ev=events[this.preview];this.animate(ev);this.preview++;await new Promise(r=>setTimeout(r,ev.kind==="attack"?this.delay*1.5:this.delay));this.draw();}this.playing=false;this.draw();}
  private animate(ev:BattleEvent){if(ev.kind==="combo"){const word=document.createElement("div");word.className="bf-combo-burst";word.textContent=ev.label;document.body.append(word);word.animate([{transform:"translate(-50%,-50%) scale(.3) rotate(-8deg)",opacity:0,filter:"blur(8px)"},{transform:"translate(-50%,-50%) scale(1.25) rotate(2deg)",opacity:1,filter:"blur(0)",offset:.37},{transform:"translate(-50%,-50%) scale(1)",opacity:1,offset:.72},{transform:"translate(-50%,-65%) scale(1.2)",opacity:0}],{duration:Math.max(1100,this.delay*2),easing:"ease-out"}).onfinish=()=>word.remove();return;}if(ev.source<0||ev.target<0||ev.kind!=="attack")return;const source=this.root.querySelector<HTMLElement>(`[data-unit="${Math.floor(ev.source/3)}-${ev.source%3}"]`),target=this.root.querySelector<HTMLElement>(`[data-unit="${Math.floor(ev.target/3)}-${ev.target%3}"]`);if(!source||!target)return;const a=source.getBoundingClientRect(),b=target.getBoundingClientRect();if(this.table!.result!.units[ev.source].card.kind==="melee"){source.animate([{transform:"translate(0,0) scale(1)"},{transform:`translate(${(b.left-a.left)*.82}px,${(b.top-a.top)*.82}px) scale(1.12)`,offset:.52},{transform:"translate(0,0) scale(1)"}],{duration:this.delay*1.35,easing:"ease-in-out"});}else{const ball=document.createElement("i");ball.className="bf-projectile";ball.style.background=colors[this.table!.result!.units[ev.source].card.faction];ball.style.left=`${a.left+a.width/2}px`;ball.style.top=`${a.top+a.height/2}px`;document.body.append(ball);const anim=ball.animate([{transform:"translate(0,0) scale(.55)",opacity:.5},{transform:`translate(${b.left-a.left}px,${b.top-a.top}px) scale(1.6)`,opacity:1}],{duration:this.delay*1.2,easing:"ease-in"});anim.onfinish=()=>ball.remove();}}
  private draw(){const t=this.table;if(!t)return;const phase=t.phase;const last=t.result?.events[Math.max(0,this.preview-1)];const unit=(side:0|1,i:number)=>{const p=t.plans[side]?.[i];if(!p)return"";const v=last?.hp[side*3+i]??p.hp,s=last?.shields[side*3+i]??0;return `<div class="bf-slot"><small>${POS[i]}位 ${s?`· 护盾 ${s}`:""}</small>${this.card(BY_ID[p.id],{side,slot:i,hp:v,selected:side===0&&this.selected===i,click:phase!=="over"&&side===0?`select`:undefined})}${side===0&&phase!=="over"?`<button data-act="swap" data-n="${i}">移到这里</button>`:""}</div>`;};
    if(phase==="over"&&this.playing&&this.root.querySelector(".bf-battle-row.enemy")){
      if(last){for(let i=0;i<6;i++){const el=this.root.querySelector<HTMLElement>(`[data-unit="${Math.floor(i/3)}-${i%3}"]`);if(!el)continue;const hp=el.querySelector(".stat.hp");if(hp)hp.textContent=String(last.hp[i]);el.classList.toggle("dead",last.hp[i]<=0);const label=el.parentElement?.querySelector("small");if(label)label.textContent=`${POS[i%3]}排${last.shields[i]?` · 护盾 ${last.shields[i]}`:""}`;}const line=this.root.querySelector(".bf-offer p");if(line)line.textContent=`战斗第 ${last.tick} 拍 · ${last.label}${last.amount?` ${last.amount}`:""}`;}return;
    }
    let center="";
    if(phase==="draft")center=`<div class="bf-offer"><h2>第 ${t.round+1} 次选人</h2><p>公开两张牌，密封出价买先选权；无人出价就换一组。点卡牌可看完整说明。</p><div class="bf-offer-cards">${t.pair.map(c=>this.card(c,{click:"card-info"})).join("")}</div>${this.bidder()}</div>`;
    if(phase==="arrange")center=`<div class="bf-offer"><h2>${t.auctionWinner===0?"你赢得了先选权":"对手先选"}</h2><div class="bf-offer-cards">${t.pair.map((c,i)=>this.card(c,{click:t.auctionWinner===0?"pick":undefined})).join("")}</div>${t.auctionWinner===0?`<div class="bf-pick-buttons"><button data-act="pick" data-n="0">拿 ${t.pair[0].name}</button><button data-act="pick" data-n="1">拿 ${t.pair[1].name}</button></div>`:""}</div>`;
    if(phase==="field")center=`<div class="bf-offer"><h2>场地效果竞拍 · ${t.fieldRound+1}/3</h2><p>${t.fieldCandidate.name}：${t.fieldCandidate.text}</p><p>当前生效：${FIELDS.find(f=>f.id===t.currentField)?.name??"尚无效果"}。双方密封出价；竞拍赢家可以选择替换或保留。</p>${this.bidder()}</div>`;
    if(phase==="field-choice")center=`<div class="bf-offer"><h2>${t.planLocked[0]?"等待对方锁阵":"锁定本轮布阵"}</h2><p>${t.noFieldWinner?"双方都放弃竞拍，本轮保留当前效果。":`${t.fieldCandidate.name}：${t.fieldCandidate.text}`}</p><p>当前场地：${FIELDS.find(f=>f.id===t.currentField)?.name??"尚无效果"}</p>${!t.planLocked[0]?(t.noFieldWinner||t.fieldWinner===1?`<div class="bf-actions"><button class="primary" data-act="lock-plan">秘密锁定布阵</button></div>`:`<div class="bf-actions"><button class="primary" data-act="field-adopt">替换为新效果并锁定</button><button data-act="field-keep">保留当前并锁定</button></div>`):`<p>布阵已秘密锁定，等待对方完成。</p>`}</div>`;
    if(phase==="bet")center=`<div class="bf-offer"><h2>${t.fieldRound===0?"阵容完成 · 开始下注":t.fieldRound===3?"最终下注":"下注 · 效果轮后"}</h2><p>当前投入：你 ${t.bet[0]} · 对手 ${t.bet[1]}；本轮起始过牌各 ${t.lastRaise} 筹码的最低加注。</p><div class="bf-actions">${t.bet[0]<t.bet[1]?`<button data-act="wager" data-kind="call">跟注</button>`:`<button data-act="wager" data-kind="check">过牌</button>`}<button data-act="wager" data-kind="raise">加注 ${this.bid}</button><button class="fold" data-act="wager" data-kind="fold">弃牌</button></div><div class="bf-bid"><button data-act="bid-down">−</button><b>${this.bid}</b><button data-act="bid-up">＋</button></div></div>`;
    if(phase==="over")center=`<div class="bf-offer"><h2>${t.folded!==null?(t.folded===0?"你弃牌了":"对手弃牌了"):this.preview<(t.result?.events.length??0)?"交战中":t.result?.winner===0?"你赢了":t.result?.winner===1?"对手赢了":"平局"}</h2><p>${last?`战斗第 ${last.tick} 拍 · ${last.label} ${last.amount?`${last.amount}`:""}`:"所有人的排位、生命和技能一同揭晓"}</p><div class="bf-actions"><button data-act="${this.playing?"skip":"replay"}">${this.playing?"跳过演出":"重播"}</button><button data-act="speed">演出速度：${this.delay===620?"慢":this.delay===350?"中":"快"}</button></div></div>`;
    const selected=t.plans[0]?.[this.selected],card=selected&&BY_ID[selected.id],choices=card?CHOICE_TEXT[card.id]:undefined;const config=(['field','field-choice','bet'].includes(phase))&&card&&!t.planLocked[0]?`<div class="bf-config"><b>${card.name} · ${POS[this.selected]}排</b><span>生命 ${selected.hp} / 12</span><button data-act="hp-">−</button><button data-act="hp+">＋</button><button data-act="skill" class="${selected.enabled?"on":""}">${selected.enabled?"技能已开启":"开启技能"}</button><span>${card.skill}</span>${card.target!=="none"?`<span>目标：${card.target==="ally"?"我方":"敌方"}${POS[selected.target]}排</span>${POS.map((p,i)=>`<button class="${selected.target===i?"on":""}" data-act="target" data-n="${i}">${p}排</button>`).join("")}`:""}${card.id==="F05"?`<span>伤害目标：</span>${POS.map((p,i)=>`<button class="${(selected.target2??0)===i?"on":""}" data-act="target2" data-n="${i}">敌方${p}排</button>`).join("")}`:""}${choices?`<span>选择一种技能效果：</span>${choices.map((label,i)=>`<button class="${selected.choice===i?"on":""}" data-act="choice" data-n="${i}">${label}</button>`).join("")}`:""}<small>基础能力：${card.basic} 普通攻击伤害：${card.attack}；普通攻击间隔：${card.interval}拍。数字越小，越早攻击。近战每有一名活着的队友站在前面，攻击间隔增加2拍。</small></div>`:t.planLocked[0]&&phase!=="over"?`<div class="bf-config"><b>本轮布阵已锁定</b><span>翻开下一张效果后可以再调整。</span></div>`:"";
    const info=t.plans[0].length===3&&phase!=="over"?analyze(t.plans[0],t.base[0],t.currentField,this.wheel):null;
    const analysis=info?`<aside class="bf-analysis"><div class="bf-wheel"><b>阵容实际效果</b>${([["none","不装辅助轮"],["sync","合拍"],["rush","快攻"],["chain","连锁"],["disrupt","干扰"]] as [Wheel,string][]).map(([id,name])=>`<button class="${this.wheel===id?"on":""}" data-act="wheel" data-wheel="${id}">${name}</button>`).join("")}<button class="primary" data-act="analysis-toggle">展开说明</button></div><div class="bf-analysis-body"><div class="bf-analysis-timeline">${info.timeline.map(x=>`<span>${esc(x.text)}</span>`).join("")}</div><div class="bf-analysis-links">${info.links.length?info.links.map(x=>`<span><b>${esc(x.name)}</b> <small>${x.certainty}：${esc(x.reason)}</small></span>`).join(""):`<span>当前还没有明显的两人配合。</span>`}</div>${info.advice.length?`<div class="bf-advice">${info.advice.map(x=>`<p>${esc(x)}</p>`).join("")}</div>`:""}</div></aside>`:"";
    const analysisModal=info&&this.analysisOpen?`<div class="bf-analysis-modal"><section><button data-act="analysis-toggle">关闭 ×</button><h2>这套阵容会怎样打</h2><h3>预计出手顺序</h3>${info.timeline.map(x=>`<p>${esc(x.text)}</p>`).join("")}<h3>人物、底板与场地</h3>${info.effects.map(x=>`<p>${esc(x)}</p>`).join("")}${info.cautions.map(x=>`<p class="bf-caution">${esc(x)}</p>`).join("")}<h3>可能打出的配合</h3>${info.links.length?info.links.map(x=>`<p><b>${esc(x.name)}</b>：${esc(x.reason)}</p>`).join(""):`<p>目前还没有明显的两人配合；这不代表阵容不能赢。</p>`}${info.advice.map(x=>`<p class="bf-advice">建议：${esc(x)}</p>`).join("")}<small>这些是按你的布阵算出的预计效果。对方的排位、底板和技能都还不知道；受伤、破盾与目标存活要等开战才能确定。</small></section></div>`:"";
    const inspected=this.inspectId?BY_ID[this.inspectId]:undefined;
    const cardInfo=inspected?`<div class="bf-card-modal"><section><button data-act="card-info-close">关闭 ×</button><h2>${esc(inspected.name)}</h2><p><b>基础能力</b>：${esc(inspected.basic)}</p><p><b>技能</b>：${esc(inspected.skill)}</p><p><b>攻击方式</b>：${inspected.kind==="melee"?"近战":"远程"}；每隔${inspected.interval}拍普通攻击一次。拍数越小，攻击越早。近战每有一名活着的队友站在前面，间隔增加2拍。</p>${CHOICE_TEXT[inspected.id]?`<p><b>技能二选一</b>：${CHOICE_TEXT[inspected.id]!.map(esc).join("；")}</p>`:""}<p>金色数字表示普通攻击会造成多少伤害。普通攻击先打敌方最前面的活人；技能按牌面指定的排数生效，那里没人就无法命中。红色数字是生命。布阵时三名队友的生命合计为24点。</p></section></div>`:"";
    this.root.innerHTML=`<div class="bf-room"></div><header class="bf-head"><button data-act="exit">‹ 返回</button><strong>血 · 火 · 被遗忘之名</strong><span>公共奖池 ${t.pot}　你 ${t.stacks[0]} · 对手 ${t.stacks[1]}</span><button data-act="help">玩法</button></header><div class="bf-table"><div class="bf-roster"><b>对手 · 已买 ${t.picked[1].length}/3</b><div>${t.picked[1].map(id=>`<span>${esc(BY_ID[id].name)}</span>`).join("")}</div></div>${phase==="over"?`<div class="bf-battle-row enemy">${[0,1,2].map(i=>unit(1,i)).join("")}</div>`:""}<div class="bf-center">${center}</div>${t.plans[0].length?`<div class="bf-battle-row own">${[0,1,2].map(i=>unit(0,i)).join("")}</div>`:""}<div class="bf-roster"><b>你 · 已买 ${t.picked[0].length}/3</b><div>${t.picked[0].map(id=>`<span>${esc(BY_ID[id].name)}</span>`).join("")}</div></div></div>${analysis}${config}<footer class="bf-foot"><span>你的底板：${BASES.find(b=>b.id===t.base[0])?.name} · ${BASES.find(b=>b.id===t.base[0])?.text}</span><small>${esc(this.error||t.log.at(-1)||"每人三名人物；双方的排位、生命分配和技能设置会在开战时揭晓。")}</small></footer>${this.help?`<div class="bf-help"><section><button data-act="help">关闭 ×</button><h2>怎么玩</h2><p><b>一 · 买人</b>　每轮展示两名人物，双方暗中出价争先选权。赢家先挑一人，另一人拿剩下的人；一直选到双方各有三人。</p><p><b>二 · 悄悄布阵</b>　你们都知道彼此买了谁，但看不到对方怎么排、怎样分配24点生命、选了哪块底板，以及是否开启技能。技能若指定了某一排，那一排没人时就会落空。</p><p><b>三 · 看战斗</b>　人物按先后顺序行动。卡面上的“拍”是战斗进程的刻度，数字越小越早行动；“每8拍攻击一次”表示两次普通攻击之间相隔8拍。近战每有一名活着的队友站在前面，就要多等2拍；远程不会因此变慢。护盾会先替你承受伤害；治疗最多把生命补满。每份着火会在后续造成两次灼烧伤害。近战冲向敌人、远程投出光球只是演出，人物不会换排。</p><p><b>四 · 下注猜阵</b>　每翻出一张新场地，双方都可以下注。三轮场地竞拍结束后不再翻新场地。观察对方买了哪些人物和当前场地，猜测他们会怎样布阵，再决定跟注、加注或弃牌。技能只有开启后才会使用；有些技能可以二选一，选项会写在卡面上。</p></section></div>`:""}${analysisModal}${cardInfo}`;
  }
  private bidder(){return `<div class="bf-bid"><button data-act="bid-down">−</button><b>${this.bid}</b><button data-act="bid-up">＋</button><button class="primary" data-act="bid">密封出价</button><button data-act="pass">跳过</button></div>`;}
}
