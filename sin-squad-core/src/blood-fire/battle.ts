import { BY_ID, type Card } from "./content.js";
import { triggeredCombos } from "./combos.js";

export type Plan = { id:string; hp:number; enabled:boolean; target:0|1|2; target2?:0|1|2; choice:0|1 };
export type Side = { units:Plan[]; base:string };
export type Unit = { card:Card; side:0|1; slot:number; hp:number; max:number; shield:number; next:number; skillNext:number; cycleStarted:boolean; attacks:number; first:boolean; bonus:number; bloodLost:number; deathStacks:number; shieldLost:number; wounded:boolean; promise:boolean; morph:boolean; marked:boolean; remember:boolean; used:boolean; plan:Plan };
export type Event = { tick:number; kind:"attack"|"damage"|"heal"|"shield"|"pace"|"burn"|"combo"|"death"|"skill"; source:number; target:number; amount:number; requested?:number; label:string; hp:[number,number,number,number,number,number]; shields:[number,number,number,number,number,number] };
export type Result = { winner:0|1|null; tick:number; events:Event[]; units:Unit[]; abnormal?:string };

export function battle(sides:[Side,Side], field:string|null):Result {
  const units:Unit[] = sides.flatMap((side,si)=>side.units.map((plan,slot)=>({card:BY_ID[plan.id],side:si as 0|1,slot,hp:plan.hp,max:plan.hp,shield:0,next:0,skillNext:0,cycleStarted:false,attacks:0,first:false,bonus:0,bloodLost:0,deathStacks:0,shieldLost:0,wounded:false,promise:false,morph:false,marked:false,remember:false,used:false,plan})));
  if(units.length!==6 || units.some(u=>!u.card || u.max<4 || u.max>12) || sides.some(s=>s.units.reduce((n,p)=>n+p.hp,0)!==24)) throw Error("非法阵容或生命分配");
  const events:Event[]=[];
  const later:{at:number;run:()=>void}[]=[];
  let tick=0, work=0, abnormal:string|undefined;
  let lastChangeTick=0;
  const lastHp=units.map(u=>u.hp),lastShields=units.map(u=>u.shield);
  const letterUsed=[false,false];
  const burning=new Map<Unit,number>();
  const lastOutput:[{kind:"damage"|"heal"|"shield"|"burn"|"pace";amount:number;slot:number;side:number}|null,{kind:"damage"|"heal"|"shield"|"burn"|"pace";amount:number;slot:number;side:number}|null]=[null,null];
  const alive=(side:number)=>units.filter(u=>u.side===side&&u.hp>0);
  const front=(side:number)=>alive(side)[0];
  const slot=(side:number,p:number)=>units.find(u=>u.side===side&&u.slot===p&&u.hp>0);
  const enemy=(u:Unit)=>front(1-u.side);
  const idx=(u?:Unit)=>u?units.indexOf(u):-1;
  const record=(kind:Event["kind"],source:Unit|undefined,target:Unit|undefined,amount:number,label:string,requested?:number)=>{const hp=units.map(u=>u.hp) as Event["hp"],shields=units.map(u=>u.shield) as Event["shields"];if(hp.some((n,i)=>n!==lastHp[i])||shields.some((n,i)=>n!==lastShields[i])){lastChangeTick=tick;hp.forEach((n,i)=>lastHp[i]=n);shields.forEach((n,i)=>lastShields[i]=n);}events.push({tick,kind,source:idx(source),target:idx(target),amount,...(requested===undefined?{}:{requested}),label,hp,shields});resolveComboRewards();};
  const chargeLostShield=(target:Unit,amount:number)=>{if(field!=="E08"||amount<=0)return;target.shieldLost+=amount;const gains=Math.min(2,Math.floor(target.shieldLost/2));if(gains){target.bonus=Math.min(2,target.bonus+gains);target.shieldLost%=2;}};
  const awardedRoutes=new Set<string>();
  const announcedSyncRoutes=new Set<string>();
  let resolvingComboRewards=false;
  let resolveComboRewards=()=>{};
  const schedule=(delay:number,run:()=>void)=>later.push({at:tick+delay,run});
  const pace=(source:Unit,target:Unit,n:number,label:string)=>{if(target.hp<=0)return; const old=target.next; if(n<0&&field==="E20")n--;target.next=Math.max(tick+1,target.next+n);const shift=target.next-old;if(shift){if(target.card.timing==="cycle"&&!target.cycleStarted)target.skillNext=Math.max(tick+1,target.skillNext+shift);record("pace",source,target,shift,label);if(n<0&&sides[target.side].base==="P03")shield(source,target,1,"无名剧院");if(n<0&&field==="E20")damage(source,target,1,"急行军·代价");if(n>0&&source.card.id==="N05"&&source!==target)shield(source,source,1,"延迟得盾");}};
  const shield=(source:Unit,target:Unit,n:number,label:string,transferred=false)=>{if(target.hp<=0)return; if(n>0&&transferred&&field==="E01")n+=Math.min(3,n);if(n>0&&field==="E15"&&source!==target&&source.side===target.side)n+=Math.min(2,Math.abs(source.slot-target.slot));if(n>0&&(field==="E06"||field==="E12"))n=Math.max(0,n-1); const take=Math.min(target.shield,Math.max(0,-n));const actual=n<0?-take:n;target.shield+=actual;if(actual)record("shield",source,target,actual,label);if(actual>0&&field==="E12")pace(source,target,-1,"轻甲快行");if(actual<0)chargeLostShield(target,take);};
  const heal=(source:Unit,target:Unit,n:number,label:string)=>{
    if(target.hp<=0)return;
    if(target.promise){target.promise=false;target=front(target.side)??target;n+=2;}
    if(source!==target&&source.side===target.side&&field==="E15")n+=Math.min(2,Math.abs(source.slot-target.slot));
    if(target.wounded&&field==="E09"){n++;target.wounded=false;}
    const actual=Math.min(n,target.max-target.hp);target.hp+=actual;record("heal",source,target,actual,label,n);
    if(field==="E11"&&n>actual)shield(source,target,Math.min(2,n-actual),"过量处方");
    if(sides[target.side].base==="P04"&&n>actual)target.bonus=Math.min(2,target.bonus+Math.floor((n-actual)/2));
    if(actual){if(target.card.id==="B01")shield(target,target,1,"血契");for(const u of alive(target.side)){if(u!==target&&u.card.id==="B02")u.bonus=Math.min(2,u.bonus+1);if(u!==target&&u.card.id==="B08"&&actual>=2)heal(u,u,1,"继承");}}
  };
  const die=(source:Unit,target:Unit)=>{record("death",source,target,0,"阵亡");for(const u of alive(target.side)){if(u.card.id==="B10")heal(u,u,2,"葬礼");if(u.card.id==="N02"&&front(target.side))pace(u,front(target.side)!,-1,"接班");if(u.card.id==="N03")u.deathStacks=Math.min(2,u.deathStacks+1);if(u.card.id==="N09")u.bonus=Math.min(2,u.bonus+1);}if(sides[target.side].base==="P02"&&front(target.side))front(target.side)!.bonus++;if(target.card.id==="F10"){if(target.morph){const v=front(1-target.side);if(v)burn(target,v,2,"不熄者");}else for(const u of alive(1-target.side))burn(target,u,1,"不熄者");}if(target.card.id==="B10"&&target.plan.enabled){if(target.plan.choice===0)for(const u of alive(target.side))heal(target,u,3,"最后一席");else if(enemy(target))damage(target,enemy(target)!,4,"最后一席");}if(target.marked&&enemy(target))damage(target,enemy(target)!,target.card.attack,"刻名");if(field==="E13")for(const u of alive(target.side))pace(target,u,-1,"谢幕掌声");};
  const damage=(source:Unit,target:Unit,n:number,label:string,attack=false,burnHit=false):number=>{
    if(target.hp<=0||n<=0)return 0;
    if(!attack&&source===target&&field==="E18"&&front(source.side)===source&&enemy(source))target=enemy(source)!;
    if(attack&&target.card.id==="N08"&&!target.used){n=Math.max(0,n-1);target.used=true;}
    const before=target.hp,beforeShield=target.shield;
    const pierce=attack&&source.card.id==="F07"&&source.morph&&source.attacks===0?Math.min(2,n):0;
    const ordinary=n-pierce;
    const shieldUnit=!attack&&field==="E07"?2:1;
    const shieldLoss=Math.min(target.shield,Math.ceil(ordinary/shieldUnit));
    target.shield-=shieldLoss;
    chargeLostShield(target,shieldLoss);
    const hpLoss=Math.min(target.hp,pierce+Math.max(0,ordinary-shieldLoss*shieldUnit));
    target.hp-=hpLoss;
    record(burnHit?"burn":"damage",source,target,hpLoss,label);
    if(beforeShield>0&&target.shield===0&&shieldLoss>0){
      if(field==="E06"&&enemy(target))damage(target,enemy(target)!,2,"薄冰碎裂");
      if(target.card.id==="N04")pace(target,target,-1,"借名者");
      for(const u of alive(target.side)){if(u.card.id==="N07"&&u!==target)shield(u,u,2,"失物招领");if(u.card.id==="F08"){const marked=source.side!==target.side?source:front(1-target.side);if(marked)burn(u,marked,1,"火线织工");}}
    }
    if(shieldLoss>0&&field==="E17")pace(target,target,-2,"缓冲地带");
    if(hpLoss>0){
      target.wounded=true;
      if(source===target&&field==="E10"&&front(target.side))shield(source,front(target.side)!,Math.min(2,hpLoss),"血不能白流");
      if(source!==target&&source.side!==target.side&&sides[target.side].base==="P02")target.bonus++;
      if(target.card.id==="B09"&&target.hp>0&&(!target.morph?source.side!==target.side:true))heal(target,target,1,"绯红自愈");
      if(target.card.id==="B04"&&alive(target.side).length>1){const rear=alive(target.side).at(-1)!;if(rear!==target)shield(target,rear,1,"伤口诗");}
      if(target.hp>0&&sides[target.side].base==="P05"&&before>target.max/2&&target.hp<=target.max/2)pace(target,target,-2,"逆旅门");
      if(source===target)for(const u of alive(source.side))if(u.card.id==="B07")u.bloodLost=Math.min(4,u.bloodLost+hpLoss);
      if(burnHit)for(const u of alive(source.side)){if(u.card.id==="F02")shield(u,u,1,"炉膛");if(u.card.id==="F06")heal(u,alive(u.side).sort((a,b)=>a.hp/a.max-b.hp/b.max)[0],1,"余温");}
    }
    if(target.hp<=0)die(source,target);
    return Math.max(0,ordinary-shieldLoss*shieldUnit-(before-pierce));
  };
  const burn=(source:Unit,target:Unit,n:number,label:string)=>{if(field==="E04"){damage(source,target,n*2,label,false,true);return;}burning.set(target,(burning.get(target)??0)+2);record("burn",source,target,n,`${label}·点燃`);for(let k=1;k<=2;k++)schedule(k*(field==="E05"?3:2),()=>{burning.set(target,Math.max(0,(burning.get(target)??0)-1));const t=slot(target.side,target.slot);if(t===target)damage(source,t,n+(field==="E05"?1:0),label,false,true);});if(field==="E03"){const next=alive(target.side).find(u=>u.slot>target.slot);if(next)for(let k=1;k<=2;k++)schedule(k*2,()=>{if(next.hp>0)damage(source,next,1,"火借风势",false,true);});}};
  let replaySaved:(source:Unit)=>void=()=>{};
  const out=(source:Unit,target:Unit|undefined,kind:"damage"|"heal"|"shield"|"burn",n:number,label:string,onHealthDamage?:()=>void)=>{
    if(!target||n<=0)return;
    const fn=()=>{
      if(target.hp<=0)return;
      const before=target.hp,shields=target.shield;
      if(kind==="damage")damage(source,target,n,label);
      if(kind==="heal")heal(source,target,n,label);
      if(kind==="shield")shield(source,target,n,label);
      if(kind==="burn")burn(source,target,n,label);
      const dealtHealthDamage=kind==="damage"&&target.hp<before;
      if(dealtHealthDamage&&field==="E02"){const next=alive(target.side).find(u=>u.slot>target.slot);if(next)damage(source,next,1,"余波");}
      if(dealtHealthDamage)onHealthDamage?.();
      const succeeded=kind==="burn"?target.hp>0:target.hp!==before||target.shield!==shields;
      if(!succeeded)return;
      if(source.card.id!=="N06")lastOutput[source.side]={kind,amount:n,slot:target.slot,side:target.side};
      replaySaved(source);
      if((label==="记住·回放"||label==="倒写")&&source.card.id!=="N06"){
        const frontAlly=front(source.side);
        if(frontAlly)for(const ally of alive(source.side))if(ally!==source&&ally.card.id==="N06")heal(ally,frontAlly,1,"倒写史官");
      }
    };
    if(sides[source.side].base==="P06"&&!letterUsed[source.side]){letterUsed[source.side]=true;n=Math.floor(n*1.5);schedule(2,fn);return;}
    if(field==="E16"&&kind!=="burn"&&n>1){const half=Math.ceil(n/2),rest=n-half;n=half;fn();if(rest)schedule(2,()=>out(source,target,kind,rest,label+"·余音",onHealthDamage));return;}
    fn();
  };
  replaySaved=(source)=>{if(!source.remember)return;const saved=lastOutput[source.side];if(!saved)return;source.remember=false;schedule(2,()=>{const target=slot(saved.side,saved.slot);if(!target)return;if(saved.kind==="pace"){const before=target.next;pace(source,target,saved.amount,"记住·回放");if(target.next!==before&&source.card.id!=="N06"){const frontAlly=front(source.side);if(frontAlly)for(const ally of alive(source.side))if(ally!==source&&ally.card.id==="N06")heal(ally,frontAlly,1,"倒写史官");}}else out(source,target,saved.kind,saved.amount,"记住·回放");});};
  const shieldOut=(source:Unit,target:Unit|undefined,n:number,label:string,transferred=false)=>{if(!target||n<=0||target.hp<=0)return;const before=target.shield;shield(source,target,n,label,transferred);if(target.shield>before){if(source.card.id!=="N06")lastOutput[source.side]={kind:"shield",amount:n,slot:target.slot,side:target.side};replaySaved(source);}};
  const paceOut=(source:Unit,target:Unit|undefined,n:number,label:string)=>{if(!target||target.hp<=0)return;const before=target.next;pace(source,target,n,label);if(target.next!==before){if(source.card.id!=="N06")lastOutput[source.side]={kind:"pace",amount:n,slot:target.slot,side:target.side};replaySaved(source);}};
  resolveComboRewards=()=>{
    if(resolvingComboRewards)return;
    resolvingComboRewards=true;
    try {
      while(true){
        const route=triggeredCombos(units,events,[sides[0].base,sides[1].base],field).find(candidate=>!awardedRoutes.has(candidate.id)&&!candidate.chapter.match(/^C2[6-9]$/));
        if(!route)break;
        const cards=route.members.filter(id=>/^[BFN]\d{2}$/.test(id));
        const source=units.find(u=>cards.includes(u.card.id));
        if(!source)continue;
        awardedRoutes.add(route.id);
        events.push({tick,kind:"combo",source:idx(source),target:-1,amount:1,label:route.name,hp:units.map(u=>u.hp) as Event["hp"],shields:units.map(u=>u.shield) as Event["shields"]});
        const ownFront=front(source.side);
        const enemyFront=front(1-source.side);
        const hurt=alive(source.side).sort((a,b)=>a.hp/a.max-b.hp/b.max||a.slot-b.slot)[0];
        switch(route.chapter){
          case "C01": case "C04": case "C06": case "C09": case "C11": case "C13": case "C15": case "C17": case "C19": case "C21": case "C25":
            if(ownFront)shield(source,ownFront,1,`配合奖励·${route.name}`);
            break;
          case "C02": case "C05": case "C08": case "C10": case "C16": case "C20": case "C24":
            if(ownFront)pace(source,ownFront,-1,`配合奖励·${route.name}`);
            break;
          case "C03": case "C07": case "C12": case "C14": case "C18": case "C22": case "C23":
            if(hurt)heal(source,hurt,1,`配合奖励·${route.name}`);
            break;
        }
        // Rewards are real outputs and may complete a different named route.
      }
    } finally { resolvingComboRewards=false; }
  };
  const skill=(u:Unit)=>{if(!u.plan.enabled||u.hp<=0)return;const ally=slot(u.side,u.plan.target),foe=slot(1-u.side,u.plan.target),e=enemy(u),choice=u.plan.choice;const skillEventStart=events.length;record("skill",u,ally??foe,0,u.card.skill.split("：")[0]);switch(u.card.id){
    case "B01":damage(u,u,2,"借命·代价");out(u,ally,"heal",4,"借命");break;
    case "B02":if(choice===0)for(const v of alive(u.side))out(u,v,"heal",2,"分席");else out(u,alive(u.side).sort((a,b)=>a.hp/a.max-b.hp/b.max)[0],"heal",4,"分席");break;
    case "B03":out(u,ally,"heal",2,"缝合");schedule(2,()=>out(u,slot(u.side,u.plan.target),"heal",2,"缝合·续"));break;
    case "B04":{const n=Math.min(3,u.shield);shield(u,u,-n,"开口");if(n&&e){record("combo",u,e,n,"铸盾为刃");pace(u,u,-1,"铸盾为刃");}out(u,e,"damage",n,"开口");break;}
    case "B05":out(u,ally,"shield",3,"挡在前面");pace(u,u,1,"盾的代价");break;
    case "B06":damage(u,u,1,"放血·代价");out(u,foe,"damage",2,"放血");break;
    case "B07":if(ally){const amount=2+u.bloodLost;u.bloodLost=0;out(u,ally,"heal",amount,"开井");}break;
    case "F05":out(u,ally,"shield",2,"卸压");out(u,slot(1-u.side,u.plan.target2??u.plan.target),"damage",2,"卸压");break;
    case "B08":u.promise=true;break;
    case "B09":u.morph=true;break;
    case "F01":if(foe)burn(u,foe,2,"火种");break;
    case "F02":u.morph=true;break;
    case "F03":if(e&&(burning.get(e)??0)>0)out(u,e,"damage",2,"趁热");break;
    case "F04":{if(foe){let delayed=false;const onHit=()=>{if(delayed)return;delayed=true;pace(u,foe,1,"烧毁日程");pace(u,foe,1,"焚信人");};out(u,foe,"damage",2,"烧毁日程",onHit);}break;}
    case "F06":if(choice===0)out(u,ally,"heal",3,"暖焰");else if(e)burn(u,e,2,"暖焰");break;
    case "F07":u.morph=true;break;
    case "F08":out(u,ally,"shield",3,"引线");if(ally)schedule(2,()=>damage(u,ally,1,"引线·代价"));break;
    case "F09":if(foe){out(u,foe,"damage",alive(foe.side).filter(v=>v!==foe&&(burning.get(v)??0)>0).length,"添柴");burn(u,foe,1,"添柴");}break;
    case "F10":u.morph=true;damage(u,u,2,"余烬之身·代价");break;
    case "N01":if(ally)ally.remember=true;break;
    case "N02":if(ally&&ally!==u)paceOut(u,ally,-2,"让拍");pace(u,u,1,"让拍·代价");break;
    case "N03":u.morph=true;break;
    case "N04":if(ally&&ally!==u){const n=Math.min(3,ally.shield);shield(u,ally,-n,"借壳");shieldOut(u,u,n,"借壳",true);out(u,ally,"heal",n,"借壳");}break;
    case "N05":if(foe)paceOut(u,foe,2,"静默");break;
    case "N06":{const previous=lastOutput[u.side];if(previous&&((choice===0&&previous.kind==="heal")||(choice===1&&previous.kind==="damage")||previous.kind==="shield"||previous.kind==="pace")){const target=slot(previous.side,previous.slot);if(previous.kind==="pace")paceOut(u,target,previous.amount,"倒写");else out(u,target,previous.kind,previous.amount,"倒写");}break;}
    case "N07":if(ally&&ally!==u){const n=Math.min(3,u.shield);shield(u,u,-n,"归还");shieldOut(u,ally,n,"归还",true);paceOut(u,ally,-1,"归还");}break;
    case "N08":shieldOut(u,u,3,"缺席");pace(u,u,2,"缺席");break;
    case "N09":if(ally&&ally!==u)ally.marked=true;break;
    case "N10":if(choice===0){damage(u,u,2,"改稿·代价");u.morph=true;}else{shieldOut(u,u,4,"改稿");u.morph=true;}break;
  }const sourceIndex=idx(u),produced=events.slice(skillEventStart+1).some(event=>event.source===sourceIndex&&((event.amount>0&&(event.kind==="heal"||event.kind==="shield"||event.kind==="burn"||(event.kind==="damage"&&event.target!==sourceIndex)))||(event.kind==="pace"&&event.amount!==0)));if(produced)for(const v of alive(u.side))if(v!==u&&v.card.id==="N01")shield(v,v,1,"无名见证");};
  for(const u of units){u.next=u.card.interval+(u.card.kind==="melee"?2*u.slot:0);u.skillNext=u.next;}
  for(const u of units)if(u.card.id==="N01"&&u.plan.enabled)skill(u);
  for(const u of units)if(u.card.id!=="N01"&&u.card.timing==="start"&&u.plan.enabled)skill(u);
  if(field==="E14")for(const side of [0,1]){const u=front(side);if(u){if(u.shield)pace(u,u,-1,"接班人");else shield(u,u,2,"接班人");}}
  while(alive(0).length&&alive(1).length){if(++work>12000){abnormal="事件链超出诊断上限";break;}const live=alive(0).concat(alive(1));const next=Math.min(...live.map(u=>u.next),...live.filter(u=>u.plan.enabled&&u.card.timing==="cycle").map(u=>u.skillNext),...later.map(x=>x.at));if(!Number.isFinite(next))break;if(next>120){abnormal="达到120刻工程上限，按平局结束";break;}tick=next;for(const x of later.filter(x=>x.at===tick)){x.run();work++;}for(let i=later.length-1;i>=0;i--)if(later[i].at===tick)later.splice(i,1);for(const u of units)if(u.hp>0&&u.plan.enabled&&u.card.timing==="cycle"&&u.skillNext<=tick){skill(u);u.cycleStarted=true;u.skillNext=tick+u.card.skillInterval!;}const attackers=units.filter(u=>u.hp>0&&u.next<=tick);for(const u of attackers)if(!u.first){u.first=true;if(u.card.timing==="first")skill(u);if(u.card.id==="F02"&&u.morph){const n=Math.min(4,u.shield),target=enemy(u);shield(u,u,-u.shield,"出炉");if(target&&n>0)out(u,target,"damage",n,"出炉");}}const ready=attackers.filter(u=>u.hp>0&&u.next<=tick);const targets=new Map(ready.map(u=>[u,enemy(u)]));for(const u of ready){const t=targets.get(u);if(!t||t.hp<=0)continue;let n=u.card.attack+u.bonus;u.bonus=0;if(u.card.id==="B06"&&u.hp/u.max>t.hp/t.max)n++;if(u.card.id==="F07"&&t.shield)n++;if(u.card.id==="F09"&&[...burning].some(([v,count])=>v.side!==u.side&&count>0))n++;if(u.card.id==="F02"&&u.morph)n++;if(u.card.id==="F10"&&u.morph)n++;if(u.card.id==="N03")n=u.morph?Math.min(4,2+u.deathStacks):Math.max(1,n-u.deathStacks);if(u.card.id==="B09"&&u.morph)n--;if(u.card.id==="N10"&&u.morph&&u.attacks<2)n+=u.plan.choice===0?1:-1;const overflow=damage(u,t,n,"普攻",true);record("attack",u,t,n,"普攻");if(overflow&&field==="E19")shield(u,u,Math.min(2,overflow),"最后一寸");if(overflow&&sides[u.side].base==="P01"&&enemy(u))damage(u,enemy(u)!,Math.min(2,overflow),"余烬炉");u.attacks++;if(u.card.id==="B03"&&front(u.side))heal(u,front(u.side)!,1,"缝心");if((u.card.id==="B05"||u.card.id==="F05")&&u.hp>0)damage(u,u,1,"普攻·自伤");if(u.card.id==="N10")shield(u,u,1,"昨日余像");if(u.card.id==="F01"&&u.attacks===1&&t.hp>0)burn(u,t,1,"引火童");u.next=tick+u.card.interval+(u.card.kind==="melee"?2*alive(u.side).filter(v=>v.slot<u.slot).length:0);}
    const performed=events.filter(e=>e.tick===tick&&e.kind==="attack").map(e=>units[e.source]);
    for(const side of [0,1] as const){
      const group=performed.filter(u=>u.side===side);
      for(let i=0;i<group.length;i++)for(let j=i+1;j<group.length;j++){
        const a=group[i],b=group[j];
        if(a.card.kind==="melee"&&b.card.kind==="melee"){
          if(a.hp>0)a.bonus++;if(b.hp>0)b.bonus++;
          record("combo",a,b,2,"并刃");
        }else if(a.card.kind==="ranged"&&b.card.kind==="ranged"){
          const hurt=alive(side).sort((x,y)=>x.hp/x.max-y.hp/y.max)[0];
          if(hurt)heal(a,hurt,2,"齐射续援");
          record("combo",a,b,2,"齐射续援");
        }else{
          if(front(side))shield(a,front(side)!,2,"交叉掩护");
          record("combo",a,b,2,"交叉掩护");
        }
      }
      if(group.length===3){for(const u of group)if(u.hp>0)pace(u,u,-1,"三重奏");record("combo",group[0],group[2],3,"三重奏");}
      for(const route of triggeredCombos(units,events,[sides[0].base,sides[1].base],field)){
        const label=route.chapter==="C26"?"并刃":route.chapter==="C27"?"交叉掩护":route.chapter==="C28"?"齐射续援":route.chapter==="C29"?"三重奏":null;
        if(!label||announcedSyncRoutes.has(`${route.id}@${tick}`))continue;
        const members=route.attackers.length?route.attackers:route.members.filter(id=>/^[BFN]\d{2}$/.test(id));
        const current=events.filter(e=>e.kind==="attack"&&e.tick===tick&&units[e.source]?.side===side).map(e=>units[e.source].card.id);
        const required=[...members];
        if(!events.some(e=>e.kind==="combo"&&e.label===label&&e.tick===tick&&units[e.source]?.side===side))continue;
        const eligible=current.filter(id=>{
          const kind=units.find(u=>u.side===side&&u.card.id===id)?.card.kind;
          return route.chapter==="C29"||(route.chapter==="C26"?kind==="melee":route.chapter==="C28"?kind==="ranged":true);
        });
        if(required.some(id=>{const at=eligible.indexOf(id);if(at<0)return true;eligible.splice(at,1);return false;}))continue;
        const roster=units.filter(u=>u.side===side).map(u=>u.card.id);
        if(route.members.filter(id=>/^[BFN]\d{2}$/.test(id)).some(id=>{const at=roster.indexOf(id);if(at<0)return true;roster.splice(at,1);return false;}))continue;
        announcedSyncRoutes.add(`${route.id}@${tick}`);
        const source=units.findIndex(u=>u.side===side&&members.includes(u.card.id)&&events.some(e=>e.kind==="attack"&&e.tick===tick&&e.source===units.indexOf(u)));
        events.push({tick,kind:"combo",source,target:-1,amount:1,label:route.name,hp:units.map(u=>u.hp) as Event["hp"],shields:units.map(u=>u.shield) as Event["shields"]});
      }
    }
    if(tick-lastChangeTick>=30&&later.length===0)break;
  }
  const winner=alive(0).length&&alive(1).length?null:alive(0).length?0:alive(1).length?1:null;
  return {winner,tick,events,units,abnormal};
}
