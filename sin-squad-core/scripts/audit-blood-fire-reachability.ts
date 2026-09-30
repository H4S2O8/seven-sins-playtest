import { battle, type Plan } from "../src/blood-fire/battle.js";
import { BASES, BY_ID, CARDS, FIELDS } from "../src/blood-fire/content.js";
import { COMBO_ROUTES } from "../src/blood-fire/combo-routes.js";
import { possibleCombos } from "../src/blood-fire/combos.js";

const samples = Math.max(1, Number(process.argv[2] ?? 1000));
const targetedAttempts = process.argv.includes("--targeted") ? 24 : 0;
let state = 0x6d2b79f5;
const random = (limit: number) => {
  state = (Math.imul(state, 1664525) + 1013904223) >>> 0;
  return state % limit;
};
const byName = new Map(COMBO_ROUTES.map(route => [route.name, route]));
const eligible = new Map<string, number>();
const emitted = new Map<string, number>();
const abnormalities: string[] = [];

for (let hand = 0; hand < samples; hand++) {
  const baseIds = [BASES[random(BASES.length)].id, BASES[random(BASES.length)].id] as [string, string];
  const field = FIELDS[random(FIELDS.length)].id;
  const sides = ([0, 1] as const).map(side => ({
    base: baseIds[side],
    units: Array.from({ length: 3 }, (_, slot): Plan => ({
      id: CARDS[random(CARDS.length)].id,
      hp: 8,
      enabled: random(2) === 0,
      target: random(3) as 0 | 1 | 2,
      choice: random(2) as 0 | 1,
    })),
  })) as [{ base: string; units: Plan[] }, { base: string; units: Plan[] }];

  for (const side of [0, 1] as const) {
    for (const route of possibleCombos(sides[side].units, sides[side].base, field)) {
      eligible.set(route.id, (eligible.get(route.id) ?? 0) + 1);
    }
  }
  const result = battle(sides, field);
  if (result.abnormal) abnormalities.push(result.abnormal);
  for (const event of result.events) {
    if (event.kind !== "combo") continue;
    const route = byName.get(event.label);
    if (route) emitted.set(route.id, (emitted.get(route.id) ?? 0) + 1);
  }
}

const targeted = new Map<string, number>();
const targetedImpossible: string[] = [];
for (const route of COMBO_ROUTES) {
  if (!targetedAttempts) break;
  const cards = route.members.filter(member => /^[BFN]\d{2}$/.test(member));
  const bases = route.members.filter(member => /^P\d{2}$/.test(member));
  const fields = route.members.filter(member => /^E\d{2}$/.test(member));
  if (cards.length > 3 || bases.length > 1 || fields.length > 1) {
    targetedImpossible.push(route.id);
    continue;
  }
  const baseChoices = bases.length ? BASES.filter(item => item.id === bases[0]) : [{ id: "NONE" }];
  const fieldChoices = fields.length ? FIELDS.filter(item => item.id === fields[0]) : [];
  let found = false;
  for (let attempt = 0; attempt < targetedAttempts && !found; attempt++) {
    const baseIds = [baseChoices[0].id, "NONE"] as [string, string];
    const field = fieldChoices.length ? fieldChoices[0].id : null;
    const ownIds = route.chapter === "C16" ? ["F08", ...cards] : route.id === "167" ? ["F08", ...cards] : route.id === "166" ? ["F08", ...cards] : route.id === "091" ? ["B04", "F08", ...cards.filter(id=>id!=="B04"&&id!=="F08")] : [...cards];
    if (route.id === "164") ownIds.push("F01");
    if ((route.id === "166" || route.id === "189") && !ownIds.includes("F08")) ownIds.push("F08");
    if (route.id === "190") ownIds.push("B05", "F08");
    while (ownIds.length < 3) {
      const candidate = CARDS[(Number(route.id) * 7 + attempt * 11 + ownIds.length * 13) % CARDS.length].id;
      ownIds.push(candidate);
    }
    const hp = route.id === "142" ? [4, 10, 10] : route.id === "127" ? [12, 4, 8] : [8, 8, 8];
    const ownUnits = ownIds.map((id, slot): Plan => ({
      id, hp: hp[slot], enabled: !(route.id === "091" && id === "B04") && !(["201", "202", "204"].includes(route.id) && id === "B05") && !(route.id === "164" && id === "F02") && !(route.id === "127" && (id === "F01" || id === "F08")),
      target: route.id === "201" && id === "N02" ? 1 : ["002", "006"].includes(route.id) && ["B07", "N02"].includes(id) ? 0 : route.id === "091" && id === "F08" ? 0 : route.id === "166" && id === "F08" ? ownIds.indexOf("N07") as 0 | 1 | 2 : (route.chapter === "C16" || route.id === "162" || route.id === "167") && id === "F08" && slot === 0 ? 0 : route.id === "190" && (id === "B05" || id === "F08") ? 0 : route.chapter === "C24" && id === "F08" && ownIds.includes("B04") ? ownIds.indexOf("B04") as 0 | 1 | 2 : BY_ID[id].target === "ally" ? ((slot + attempt + 1) % 3) as 0 | 1 | 2 : 0,
      choice: (attempt % 2) as 0 | 1,
    }));
    const needsShieldedTarget = route.chapter === "C16" && !fields.includes("E19");
    const wantsOverflow = bases.includes("P01");
    const needsShieldInteraction = route.chapter === "C07" || ["091", "162", "163", "166", "167"].includes(route.id);
    const foeIds = needsShieldedTarget || needsShieldInteraction ? ["B05", "B05", "B05"] : wantsOverflow ? ["B05", "N06", "N06"] : ["N06", "N06", "N06"];
    const foeUnits = foeIds.map((id, slot): Plan => ({
      id, hp: wantsOverflow ? [4, 10, 10][slot] : route.id === "123" ? [6, 9, 9][slot] : 8,
      enabled: id === "B05",
      target: needsShieldedTarget ? 0 : wantsOverflow ? 1 : needsShieldInteraction ? (slot+1)%3 : slot, choice: 0,
    }));
    const result = battle([{ base: baseIds[0], units: ownUnits }, { base: "NONE", units: foeUnits }], field);
    if (result.events.some(event => event.kind === "combo" && event.label === route.name)) found = true;
  }
  if (found) targeted.set(route.id, 1);
}

const missing = COMBO_ROUTES.filter(route => !emitted.has(route.id));
const eligibleButSilent = COMBO_ROUTES.filter(route => eligible.has(route.id) && !emitted.has(route.id));
const result = {
  scope: "fixed-seed random battles plus targeted per-route scenarios; targeted output proves a route can announce under at least one constructed context, not that the description is causally exact, balanced, or fun",
  samples,
  uniqueRoutesEmitted: emitted.size,
  eligibleRoutesObserved: eligible.size,
  targetedRouteSetups: targetedAttempts,
  targetedRoutesEmitted: targeted.size,
  targetedNeverEmitted: targetedAttempts ? COMBO_ROUTES.filter(route => !targeted.has(route.id)).map(route => ({ id: route.id, name: route.name })) : [],
  structurallyImpossible: targetedImpossible,
  eligibleButSilent: eligibleButSilent.map(route => ({ id: route.id, name: route.name, exposures: eligible.get(route.id) })),
  neverEligible: COMBO_ROUTES.filter(route => !eligible.has(route.id)).map(route => ({ id: route.id, name: route.name })),
  missingNames: missing.map(route => ({ id: route.id, name: route.name })),
  eventChainsOverLimit: abnormalities.length,
  distinctAbnormalities: [...new Set(abnormalities)],
};
console.log(JSON.stringify(result, null, 2));
