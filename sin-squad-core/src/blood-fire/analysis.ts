import { BASES, BY_ID, CHOICE_TEXT, FIELDS } from "./content.js";
import type { Plan } from "./battle.js";
import { possibleCombos } from "./combos.js";

export type Wheel="none"|"sync"|"rush"|"chain"|"disrupt";
export type Analysis={timeline:{slot:number;tick:number;text:string}[];effects:string[];links:{name:string;reason:string;certainty:"确定"|"条件"}[];cautions:string[];advice:string[]};
const pos=["前","中","后"];
const selfHarm=new Set(["B01","B05","B06","F05","F10","N10"]);
const fireSource=new Set(["F01","F03","F06","F08","F09","F10"]);
const shieldSource=new Set(["B04","B05","F05","F08","N08","N10"]);
const paceSource=new Set(["N02","N04","N05","N07"]);
function plannedTimes(plans:Plan[],fieldId:string|null):number[]{
  const ticks=plans.map((p,slot)=>{const c=BY_ID[p.id];let tick=c.interval+(c.kind==="melee"?slot*2:0);if(p.enabled&&p.id==="B05")tick++;if(p.enabled&&p.id==="N08")tick+=2;if(p.enabled&&p.id==="N02")tick++;return tick;});
  const gatekeeper=plans.findIndex(p=>p.enabled&&p.id==="N02");
  if(gatekeeper>=0){const target=plans[gatekeeper].target;if(target!==gatekeeper&&plans[target])ticks[target]=Math.max(1,ticks[target]-(fieldId==="E20"?3:2));}
  return ticks;
}
/** Own-side information only. All statements are either deterministic from the plan or marked conditional. */
export function analyze(plans:Plan[],baseId:string,fieldId:string|null,wheel:Wheel="none"):Analysis{
  const ticks=plannedTimes(plans,fieldId);
  const timeline=plans.map((p,slot)=>{const c=BY_ID[p.id],tick=ticks[slot];return{slot,tick,text:`${pos[slot]}位 ${c.name}：首次普攻预计在第 ${tick} 拍${c.kind==="melee"&&slot?"（前面每有一名活队友，间隔增加2拍）":""}`};});
  const effects:string[]=[];const links:Analysis["links"]=[],cautions:string[]=[],advice:string[]=[];
  const chosen=plans.map(p=>BY_ID[p.id]);const active=plans.filter(p=>p.enabled);
  effects.push(`你把 ${plans.reduce((n,p)=>n+p.hp,0)} 点生命分成了：${plans.map((p,i)=>`${pos[i]}位 ${p.hp} 点`).join("、")}。三个人都会自己攻击，先打对面站在最前面的人。`);
  for(let i=0;i<3;i++){const p=plans[i],c=chosen[i];if(p.enabled){let aim=c.target==="none"?"不需要选目标":`指向${c.target==="ally"?"己方":"敌方"}${pos[p.target]}位`;if(c.id==="F05")aim=`护盾给己方${pos[p.target]}位，伤害打敌方${pos[p.target2??p.target]}位`;if(c.id==="F06"&&p.choice===1)aim="灼烧敌方当前前位";if(c.id==="B04")aim="消耗自己的护盾，打敌方当前前位";const choice=CHOICE_TEXT[c.id]?.[p.choice];if(choice)aim+=`；选择“${choice}”`;const when=c.timing==="start"?"开战时":c.timing==="first"?"本人首次普攻前（仅一次）":c.timing==="cycle"?`本人首次普攻前，之后每隔${c.skillInterval}拍再发动`:"阵亡时";effects.push(`${c.name}技能在${when}发动；${aim}。`);if(c.target==="ally"&&p.target===i&&["N02","N04","N07","N09"].includes(c.id))cautions.push(`${c.name}这招要给另一名队友；现在指向了自己，可能什么都做不了。`);if(c.id==="N06")cautions.push("倒写史官要先有一条成功的治疗或伤害技能记录；这套阵容不能保证记录先出现。");}else effects.push(`${c.name}没有发动技能；仍会普通攻击，基础能力也照常生效。`);}
  effects.push(`你的隐藏底板是「${BASES.find(b=>b.id===baseId)?.name??"未知"}」：${BASES.find(b=>b.id===baseId)?.text??""}`);
  if(fieldId)effects.push(`这局正在生效的场地是「${FIELDS.find(f=>f.id===fieldId)?.name??"未知"}」：${FIELDS.find(f=>f.id===fieldId)?.text??""}`);
  const harm=chosen.filter(c=>selfHarm.has(c.id)),recover=chosen.filter(c=>["B01","B02","B03","B07","B09","F06"].includes(c.id));
  if(harm.length&&recover.length&&harm.some(a=>recover.some(b=>a!==b)))links.push({name:"以血为引",certainty:"条件",reason:`${harm[0].name}可制造伤口，${recover.find(b=>b!==harm[0])?.name??recover[0].name}可接治疗；要实际扣血并救到人。`});
  if(chosen.some(c=>fireSource.has(c.id))&&chosen.some(c=>["F02","F06","F09"].includes(c.id))&&new Set(chosen.map(c=>c.id)).size>1)links.push({name:"火中取暖",certainty:"条件",reason:"一人点火、另一人利用灼烧；要等火真正扣到生命，盾挡住就不算。"});
  const shieldMaker=plans.some(p=>shieldSource.has(p.id)&&(p.enabled||["B04","N10"].includes(p.id)));
  const shieldSpent=plans.some(p=>p.enabled&&["B04","F02","N04","N07"].includes(p.id));
  if(shieldMaker&&shieldSpent&&plans.some(a=>plans.some(b=>a!==b&&shieldSource.has(a.id)&&["B04","F02","N04","N07"].includes(b.id))))links.push({name:"铸盾为刃",certainty:"条件",reason:"一个人给出护盾，另一个人把护盾花出去换成伤害或更快出手；要先拿到盾，还要活到用盾时。"});
  if(chosen.some(c=>paceSource.has(c.id))&&chosen.some(c=>c.kind==="melee"))links.push({name:"借拍登台",certainty:"条件",reason:"行动提前可帮助慢近战抢到一刀；敌人的延迟或击杀会改变实际时刻。"});
  for(let i=0;i<3;i++)for(let j=i+1;j<3;j++){const a=timeline[i],b=timeline[j];if(a.tick===b.tick)links.push({name:chosen[i].kind===chosen[j].kind?(chosen[i].kind==="melee"?"并刃":"齐射续援"):"交叉掩护",certainty:"条件",reason:`${pos[i]}位与${pos[j]}位预计在第 ${a.tick} 拍同时普攻；两人都活着且没有被延迟，才会合击。`});}
  if(new Set(timeline.map(x=>x.tick)).size===1)links.push({name:"三重奏",certainty:"条件",reason:`三人预计同在第 ${timeline[0].tick} 拍普攻；全部活着才能触发。`});
  if(fieldId==="E04"&&chosen.some(c=>fireSource.has(c.id)))effects.push("急燃会把新灼烧改为立即伤害；长期有火条件因此会减少。");
  if(fieldId==="E15"&&active.some(p=>BY_ID[p.id].target==="ally"))effects.push("隔席相赠会按固定槽距离增强对队友的治疗与护盾；自用不增加。");
  if(baseId==="P04"&&active.some(p=>["B01","B02","B03","B07"].includes(p.id)))effects.push("圣餐桌能把溢疗换成下一刀伤害；满血治疗也可能是主动进攻。");
  links.splice(0,links.length,...possibleCombos(plans,baseId,fieldId).map(route=>({name:route.name,certainty:"条件" as const,reason:`${route.condition}（参与者：${route.members.join("、")}）`})));
  if(wheel==="sync"){
    const sorted=[...timeline].sort((a,b)=>a.tick-b.tick);const gap=sorted[1].tick-sorted[0].tick;
    advice.push(gap===0?`已有同拍普攻机会：${pos[sorted[0].slot]}位和${pos[sorted[1].slot]}位。对手干扰可能打散它。`:`最近两人的首次普攻相差 ${gap} 拍。可调整近战站位或用提前行动的技能追上；不要为了同时出手牺牲前排生存。`);
  }
  if(wheel==="rush"){
    const fastest=[...timeline].sort((a,b)=>a.tick-b.tick)[0];advice.push(`最快出手：${pos[fastest.slot]}位第 ${fastest.tick} 拍。想抢首杀，可让高攻者更靠前，或把加速技能指给它。`);
    if(chosen.filter(c=>c.kind==="melee").length===3)advice.push("三近战从后位出手较慢，伤害高但先手薄弱；考虑用技能抢拍或用盾扛到后排出刀。");
  }
  if(wheel==="chain"){
    if(links.length)advice.push(`这三人之间有 ${links.length} 种可能接上的配合。先看看技能有没有打开、目标有没有指错；对手的盾也可能挡掉触发条件。`);
    else advice.push("这三人暂时没有明显的接力。下一轮可以找能接住已有治疗、火焰或护盾的人，不必硬凑同一种族。");
  }
  if(wheel==="disrupt"){
    const back=active.find(p=>BY_ID[p.id].target==="enemy"&&p.target===2);
    advice.push(back?`${BY_ID[back.id].name}已指敌后位，适合试探后排核心；若该槽空了，技能会落空。`:"目前没有主动技能指向敌后位；对手若把关键角色藏后面，你只能先靠普攻突破前位。可考虑调整有指向技能的目标槽。");
  }
  return{timeline,effects,links,cautions,advice};
}
