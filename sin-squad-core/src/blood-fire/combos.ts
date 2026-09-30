import { COMBO_ROUTES, type ComboRoute } from "./combo-routes.js";
import type { Event, Plan, Unit } from "./battle.js";

const chapterLabel = new Map([["C26", "并刃"], ["C27", "交叉掩护"], ["C28", "齐射续援"], ["C29", "三重奏"]]);

function containsCopies(values: string[], required: string[]): boolean {
  const counts = new Map<string, number>();
  for (const value of values) counts.set(value, (counts.get(value) ?? 0) + 1);
  return required.every(value => {
    const left = counts.get(value) ?? 0;
    if (left <= 0) return false;
    counts.set(value, left - 1);
    return true;
  });
}

export function possibleCombos(plans: Plan[], base: string, field: string | null): ComboRoute[] {
  const cards = plans.map(plan => plan.id);
  const environment = new Set([base, ...(field ? [field] : [])]);
  return COMBO_ROUTES.filter(route => {
    const characterIds = route.members.filter(member => /^[BFN]\d{2}$/.test(member));
    const environmentIds = route.members.filter(member => /^[PE]\d{2}$/.test(member));
    return containsCopies(cards, characterIds) && environmentIds.every(member => environment.has(member));
  });
}

function hasChapterEvidence(route: ComboRoute, side: 0 | 1, units: Unit[], events: Event[], field: string | null): boolean {
  const chapter = route.chapter;
  const own = new Set(units.map((unit, i) => unit.side === side ? i : -1).filter(i => i >= 0));
  const fromOwn = events.filter(event => own.has(event.source));
  const positive = (kind: Event["kind"]) => fromOwn.some(event => event.kind === kind && event.amount > 0);
  const hasLabel = (...labels: string[]) => fromOwn.some(event => labels.some(label => event.label.includes(label)));
  const hadShield = (i: number) => events.some(event => event.shields[i] > 0) && events.some(event => event.shields[i] === 0);
  switch (chapter) {
    case "C01": return fromOwn.some(e => e.kind === "damage" && e.source === e.target && e.amount > 0) && positive("heal");
    case "C02": return units.some((u, i) => u.side === side && u.card.id === "B02" && fromOwn.some(e => e.kind === "attack" && e.source === i && e.amount > u.card.attack));
    case "C03": return positive("burn") && hasLabel("余温");
    case "C04": return units.some((u, i) => u.side === side && hadShield(i)) && (positive("pace") || hasLabel("火线织工", "失物招领"));
    case "C05": return hasLabel("余烬炉", "最后一寸") && positive("damage");
    case "C06": return hasLabel("过量处方", "圣餐桌") && (positive("shield") || positive("attack"));
    case "C07": return hasLabel("借壳", "归还") && (positive("shield") || positive("heal"));
    case "C08": return events.some(e => e.kind === "death" && (units[e.target]?.side === side)) && (positive("heal") || positive("damage") || positive("pace"));
    case "C09": return hasLabel("记住·回放", "倒写") && (positive("heal") || positive("damage") || positive("shield") || positive("pace"));
    case "C10": return positive("pace") && positive("attack");
    case "C11": return positive("pace") && positive("attack");
    case "C12": {
      if(route.id==="091"){const f08=units.findIndex(u=>u.side===side&&u.card.id==="F08"),b04=units.findIndex(u=>u.side===side&&u.card.id==="B04");const gift=f08>=0&&b04>=0?events.findIndex(e=>e.kind==="shield"&&e.source===f08&&e.target===b04&&e.label==="引线"&&e.amount>0):-1;const cost=f08>=0&&b04>=0?events.findIndex(e=>e.kind==="damage"&&e.source===f08&&e.target===b04&&e.label==="引线·代价"):-1;const hit=b04>=0?events.findIndex(e=>e.kind==="damage"&&e.target===b04&&e.amount>0&&e.tick>(cost>=0?events[cost].tick:-1)):-1;return gift>=0&&cost>gift&&hit>=0&&events.some(e=>e.kind==="shield"&&e.source===b04&&e.label==="伤口诗"&&e.amount>0&&events.indexOf(e)>hit);}
      return fromOwn.some(e => e.kind === "damage" && e.source === e.target && e.amount > 0) && (positive("heal") || positive("shield"));
    }
    case "C13": return hasLabel("余音", "续") && (positive("shield") || positive("heal"));
    case "C14": return positive("burn") && (hasLabel("趁热", "添柴", "余温") || positive("heal"));
    case "C15": return hasLabel("卸压") && positive("damage") && positive("shield");
    case "C16": {
      const f07=units.findIndex(u=>u.side===side&&u.card.id==="F07");
      if(route.id==="123")return f07>=0&&events.some(e=>e.kind==="shield"&&e.source===f07&&e.label==="最后一寸"&&e.amount>0);
      return hasLabel("熔穿") || units.some(u => u.side === side && u.card.id === "F07" && u.plan.enabled && events.some((e, i) => e.kind === "damage" && e.source === units.indexOf(u) && e.amount > 0 && (i === 0 ? 0 : events[i - 1].shields[e.target]) > e.shields[e.target]));
    }
    case "C17": return units.some(u => u.side === side && u.morph && events.some(e => e.kind === "attack" && e.source === units.indexOf(u)));
    case "C18": return hasLabel("逆旅门") && positive("attack");
    case "C19": return positive("pace") && (positive("shield") || positive("heal"));
    case "C20": return events.some(e => e.kind === "death" && units[e.target]?.side === side) && positive("damage");
    case "C21": {
      const source = (id:string) => units.findIndex(u=>u.side===side&&u.card.id===id);
      if (route.id === "162") {const shield=events.find(e=>e.kind==="shield"&&e.source===source("F08")&&e.label==="引线"&&e.amount>0);return !!shield&&events.some(e=>e.kind==="pace"&&e.label==="缓冲地带"&&e.target===shield.target&&e.amount<0&&e.tick>=shield.tick);}
      if (route.id === "163") {const n10=source("N10");return n10>=0&&units[n10].plan.choice===1&&events.some(e=>e.kind==="shield"&&e.source===n10&&e.label==="改稿"&&e.amount>0)&&events.some((e,i)=>e.kind==="damage"&&e.target===n10&&e.shields[n10]<(i?events[i-1].shields[n10]:0))&&events.some(e=>e.kind==="attack"&&e.source===n10&&e.amount>units[n10].card.attack-1);}
      if (route.id === "164") {const f02=source("F02");return f02>=0&&!units[f02].plan.enabled&&events.some(e=>e.kind==="shield"&&e.source===f02&&e.label==="炉膛"&&e.amount>0)&&events.some((e,i)=>e.kind==="damage"&&e.target===f02&&e.shields[f02]<(i?events[i-1].shields[f02]:0))&&events.some(e=>e.kind==="attack"&&e.source===f02&&e.amount>units[f02].card.attack);}
      if (route.id === "166") {const n07=source("N07"),f02=source("F02");return n07>=0&&f02>=0&&events.some(e=>e.kind==="shield"&&e.source===n07&&e.target===f02&&e.label==="归还"&&e.amount>0)&&events.some(e=>e.kind==="damage"&&e.source===f02&&e.label==="出炉"&&e.amount>0);}
      if (route.id === "167") {const n07=source("N07");return n07>=0&&field==="E12"&&events.some(e=>e.kind==="shield"&&e.source===n07&&e.label==="失物招领"&&e.amount===1)&&events.some(e=>e.kind==="pace"&&e.source===n07&&e.target===n07&&e.label==="轻甲快行"&&e.amount<0);}
      return hasLabel("借壳", "归还", "开口") && positive("shield");
    }
    case "C22": return events.some(a => a.kind === "heal" && a.amount > 0 && events.some(b => b.kind === "heal" && b.target === a.target && b.source !== a.source && b.tick >= a.tick));
    case "C23": return events.some(e => e.kind === "damage" && units[e.target]?.side !== side && units[e.target]?.slot > 0) && positive("attack");
    case "C24": {
      if(route.id==="191"){const f08=units.findIndex(u=>u.side===side&&u.card.id==="F08"),b04=units.findIndex(u=>u.side===side&&u.card.id==="B04");const split=f08>=0&&events.some(e=>e.kind==="shield"&&e.source===f08&&e.label==="引线"&&e.amount>0)&&events.some(e=>e.kind==="shield"&&e.source===f08&&e.label==="引线·余音"&&e.amount>0);return field==="E16"&&split&&b04>=0&&events.some(e=>e.kind==="shield"&&e.source===b04&&e.label==="开口"&&e.amount<0)&&events.some(e=>e.kind==="damage"&&e.source===b04&&e.label==="开口"&&e.amount>0);}
      if (route.members.includes("F02")) {const f02=units.findIndex(u=>u.side===side&&u.card.id==="F02");const spent=f02>=0&&events.some(e=>e.kind==="shield"&&e.source===f02&&e.label==="出炉"&&e.amount<0);const blast=f02>=0&&events.some(e=>e.kind==="damage"&&e.source===f02&&e.label==="出炉"&&e.amount>0);if(route.id==="190")return field==="E08"&&spent&&blast&&events.some(e=>e.kind==="attack"&&e.source===f02&&e.amount>units[f02].card.attack+1);return spent&&blast;}
      return hasLabel("开口") && positive("damage");
    }
    case "C25": return new Set(fromOwn.filter(e => e.kind === "damage" || e.kind === "heal" || e.kind === "shield" || e.kind === "pace").map(e => e.source)).size >= 3;
    case "C26": case "C27": case "C28": case "C29": return events.some(e => e.kind === "combo" && e.label === chapterLabel.get(chapter) && units[e.source]?.side === side);
    default: return false;
  }
}

function hasC02Evidence(route: ComboRoute, side: 0 | 1, units: Unit[], events: Event[], base: string): boolean {
  const listed = new Set(route.members);
  return events.some((attack, attackIndex) => {
    if (attack.kind !== "attack" || units[attack.source]?.side !== side) return false;
    const attacker = units[attack.source];
    if (attack.amount <= attacker.card.attack) return false;
    const priorHeals = events.slice(0, attackIndex).filter(event => event.kind === "heal" && event.target === attack.source && units[event.source]?.side === side && event.requested !== undefined && event.requested > event.amount);
    const bloodHost = listed.has("B02") && attacker.card.id === "B02" && events.slice(0, attackIndex).some(event => event.kind === "heal" && event.amount > 0 && event.source !== attack.source && units[event.source]?.side === side && units[event.target]?.side === side);
    const banquetOverflow = base === "P04" && priorHeals.some(event => {
      if (listed.has("B01") && event.source === units.findIndex(unit => unit.side === side && unit.card.id === "B01")) return true;
      if (listed.has("B07") && event.source === units.findIndex(unit => unit.side === side && unit.card.id === "B07")) return true;
      if (listed.has("B02") && event.source === units.findIndex(unit => unit.side === side && unit.card.id === "B02")) return true;
      return false;
    });
    return bloodHost || banquetOverflow;
  });
}

function hasExactC01Evidence(route: ComboRoute, side: 0 | 1, units: Unit[], events: Event[]): boolean | undefined {
  const source = (id:string) => units.findIndex(u=>u.side===side&&u.card.id===id);
  const from = (id:string, test:(e:Event)=>boolean) => {const i=source(id);return events.find(e=>e.source===i&&test(e));};
  const after = (first:Event|undefined, second:Event|undefined) => !!first&&!!second&&second.tick>=first.tick&&events.indexOf(second)>events.indexOf(first);
  const selfDamage = (id:string,label:string) => from(id,e=>e.kind==="damage"&&e.target===e.source&&e.amount>0&&e.label===label);
  const wellHeal = () => from("B07",e=>e.kind==="heal"&&e.label==="开井"&&e.amount>0&&(e.requested??e.amount)>=3);
  switch(route.id){
    case "001": {const wound=selfDamage("B01","借命·代价"),heal=wellHeal();return after(wound,heal);}
    case "002": {const wound=selfDamage("B05","普攻·自伤"),n02=source("N02"),b05=source("B05"),pace=events.find(e=>e.source===n02&&e.target===b05&&e.kind==="pace"&&e.amount<0&&e.label==="让拍"),heal=wellHeal();return after(wound,heal)&&!!pace&&after(pace,heal);}
    case "003": {const n10=source("N10"),wound=selfDamage("N10","改稿·代价"),heal=wellHeal();return n10>=0&&units[n10].plan.choice===0&&after(wound,heal);}
    case "004": {const wound=selfDamage("B01","借命·代价"),b01=source("B01"),b02=source("B02"),heal=events.find(e=>e.source===b01&&e.kind==="heal"&&e.label==="借命"&&e.amount>0&&e.target!==b02),attack=events.find(e=>e.source===b02&&e.kind==="attack"&&e.amount>units[b02].card.attack);return after(wound,heal)&&after(heal,attack);}
    case "005": {const wound=selfDamage("B06","放血·代价"),b06=source("B06"),b03=source("B03"),heal=events.find(e=>e.source===b03&&e.target===b06&&e.kind==="heal"&&e.label==="缝心"&&e.amount>0);return after(wound,heal);}
    case "006": {const f05=source("F05"),n02=source("N02"),b07=source("B07"),pace=events.find(e=>e.source===n02&&e.target===f05&&e.kind==="pace"&&e.amount<0&&e.label==="让拍"),wound=events.find(e=>e.source===f05&&e.target===f05&&e.kind==="damage"&&e.amount>0&&e.label==="普攻·自伤"),heal=wellHeal();return !!pace&&!!wound&&!!heal&&after(pace,wound)&&after(wound,heal);}
    default:return undefined;
  }
}

/** Finds route names only when their chapter has observable event evidence and every listed contributor is present. */
export function triggeredCombos(units: Unit[], events: Event[], bases: [string, string], field: string | null): ComboRoute[] {
  return COMBO_ROUTES.filter(route => {
    if (route.chapter === "C26" || route.chapter === "C27" || route.chapter === "C28" || route.chapter === "C29") {
      const required = route.attackers.length ? route.attackers : route.members.filter(id => /^[BFN]\d{2}$/.test(id));
      const support = route.members.filter(id => /^[BFN]\d{2}$/.test(id)).filter(id => !route.attackers.includes(id));
      return ([0, 1] as const).some(side => {
        const byTick = new Map<number, string[]>();
        for (const event of events) if (event.kind === "attack" && units[event.source]?.side === side) {
          const ids = byTick.get(event.tick) ?? [];
          ids.push(units[event.source].card.id);
          byTick.set(event.tick, ids);
        }
        return [...byTick.entries()].some(([at, ids]) => {
          const eligible = ids.filter(id => route.chapter === "C29" || (route.chapter === "C26" ? units.find(u => u.side === side && u.card.id === id)?.card.kind === "melee" : route.chapter === "C28" ? units.find(u => u.side === side && u.card.id === id)?.card.kind === "ranged" : true));
          if (!containsCopies(eligible, required)) return false;
          if (!containsCopies(units.filter(u => u.side === side).map(u => u.card.id), route.members.filter(id => /^[BFN]\d{2}$/.test(id)))) return false;
          if (support.some(id => !events.some(e => e.tick <= at && e.source >= 0 && units[e.source]?.side === side && units[e.source]?.card.id === id && e.kind !== "attack" && (e.kind === "pace" ? e.amount < 0 : e.amount > 0)))) return false;
          const attackingKinds = required.map(id => units.find(u => u.side === side && u.card.id === id)?.card.kind);
          const melee = attackingKinds.filter(kind => kind === "melee").length;
          const ranged = attackingKinds.length - melee;
          if (route.chapter === "C26") return melee >= 2;
          if (route.chapter === "C27") return melee >= 1 && ranged >= 1;
          if (route.chapter === "C28") return ranged >= 2;
          return eligible.length >= 3;
        });
      });
    }
    return ([0, 1] as const).some(side => {
      const roster = units.filter(u => u.side === side).map(u => u.card.id);
      const environment = new Set([bases[side], ...(field ? [field] : [])]);
      const requiredCards = route.members.filter(id => /^[BFN]\d{2}$/.test(id));
      const requiredEnvironment = route.members.filter(id => /^[PE]\d{2}$/.test(id));
      if (!containsCopies(roster, requiredCards) || !requiredEnvironment.every(id => environment.has(id))) return false;
      if(route.chapter==="C01"){
        const exact=hasExactC01Evidence(route,side,units,events);
        if(exact!==undefined)return exact;
      }
      const listed = requiredCards;
      const contributors = new Set(events.filter(e => {
        if(e.source<0||units[e.source]?.side!==side||e.kind==="skill"||e.kind==="combo"||e.kind==="death")return false;
        if(e.kind==="attack")return e.amount>0&&/攻击|普攻|出手|首刀/.test(route.condition);
        if(e.kind==="pace")return e.amount!==0;
        if(route.chapter==="C02"&&bases[side]==="P04"&&e.kind==="heal"&&(e.requested??0)>e.amount)return true;
        return (e.kind==="damage"||e.kind==="heal"||e.kind==="shield"||e.kind==="burn")&&e.amount>0;
      }).map(e => units[e.source].card.id));
      if (!listed.every(id => contributors.has(id))) return false;
      if (route.chapter === "C02") return hasC02Evidence(route, side, units, events, bases[side]);
      return hasChapterEvidence(route, side, units, events, field);
    });
  });
}
