import { readFileSync, writeFileSync } from "node:fs";
import {
  characterById,
  equipmentById,
  type NumericSlot,
} from "../src/numeric/content.js";
import { type Keyword, KEYWORDS } from "../src/numeric/keywords.js";
type Row = {
  control: boolean;
  showdown: boolean;
  teams: NumericSlot[][];
  trace: any[];
};
const rows = readFileSync("reports/numeric-keywords-1000-hands.jsonl", "utf8")
  .trim()
  .split("\n")
  .map((x) => JSON.parse(x) as Row)
  .filter((r) => !r.control);
const keys = (x: NumericSlot) =>
  new Set(
    [
      ...(characterById(x.effectId).keywords ?? []),
      ...(x.equipment
        ? (equipmentById(x.equipment.id, x.equipment.tier).keywords ?? [])
        : []),
    ].map((k) => k.kind),
  );
const has = (t: NumericSlot[], k: Keyword) => t.some((x) => keys(x).has(k));
const support = (t: NumericSlot[]) =>
  t.some(
    (x) =>
      ["LU1", "LU4", "LU5", "PR3", "SL3"].includes(x.effectId) ||
      keys(x).has("link"),
  );
const devour = (t: NumericSlot[]) =>
  t.some(
    (x, p) => p > 0 && x.effectId === "GL2" && keys(t[p - 1]).has("legacy"),
  );
const protectedAlly = (t: NumericSlot[]) => has(t, "ward") || has(t, "guard");
const small = [
  ["支援→共鸣", (t: NumericSlot[]) => support(t) && has(t, "echo"), ["echo"]],
  ["任意强化→蓄能", (t: NumericSlot[]) => has(t, "reserve"), ["reserve"]],
  ["吞食→遗赠", devour, ["legacy"]],
  [
    "护送→护盾",
    (t: NumericSlot[]) =>
      t.some((x) => keys(x).has("guard") && keys(x).has("ward")),
    ["guard", "ward"],
  ],
  [
    "关键词多样性→激励",
    (t: NumericSlot[]) =>
      t.some(
        (x, p) =>
          keys(x).has("inspire") &&
          t.some((y, q) => q !== p && keys(y).size > 0),
      ),
    ["inspire"],
  ],
  [
    "护盾/护送队友→统御",
    (t: NumericSlot[]) => has(t, "command") && protectedAlly(t),
    ["command"],
  ],
  [
    "双关键词→结盟",
    (t: NumericSlot[]) =>
      t.some((x) => keys(x).has("link") && keys(x).size >= 2),
    ["link"],
  ],
  ["领先主力→追猎", (t: NumericSlot[]) => has(t, "pursuit"), ["pursuit"]],
  ["减力/截流→激怒", (t: NumericSlot[]) => has(t, "rage"), ["rage"]],
] as const;
const large = [
  [
    "吞食→遗赠→蓄能",
    (t: NumericSlot[]) => devour(t) && has(t, "reserve"),
    ["legacy", "reserve"],
  ],
  [
    "支援→共鸣→蓄能",
    (t: NumericSlot[]) => support(t) && has(t, "echo") && has(t, "reserve"),
    ["echo", "reserve"],
  ],
  [
    "双关键词结盟→共鸣→蓄能",
    (t: NumericSlot[]) =>
      t.some((x) => keys(x).has("link") && keys(x).size >= 2) &&
      has(t, "echo") &&
      has(t, "reserve"),
    ["link", "echo", "reserve"],
  ],
  [
    "护送/护盾→统御→追猎",
    (t: NumericSlot[]) =>
      protectedAlly(t) &&
      t.some((x) => keys(x).has("command") && keys(x).has("pursuit")),
    ["command", "pursuit"],
  ],
] as const;
function measure(
  families: readonly (readonly [
    string,
    (t: NumericSlot[]) => boolean,
    readonly string[],
  ])[],
) {
  return families.map(([name, eligible, required]) => {
    let prepared = 0,
      showdownPrepared = 0,
      coactivated = 0;
    for (const r of rows)
      r.teams.forEach((t, s) => {
        if (!eligible(t)) return;
        prepared++;
        if (!r.showdown) return;
        showdownPrepared++;
        if (
          required.every((k) =>
            r.trace.some(
              (e) =>
                e.stage === "keyword" &&
                e.seat === s &&
                e.text.startsWith(KEYWORDS[k as Keyword].name),
            ),
          )
        )
          coactivated++;
      });
    return {
      name,
      preparedLineups: prepared,
      showdownPreparedLineups: showdownPrepared,
      coactivatedLineups: coactivated,
    };
  });
}
const report = {
  definition:
    "Curated 9 small and 4 longer synergy families, not exhaustive card combinations. 2000 player lineups from 1000 hands. Prepared means structural ingredients present; coactivated means keyword traces occurred on that side, NOT proof each caused the next or caused a win. Families overlap; do not sum.",
  small: measure(small),
  large: measure(large),
};
writeFileSync(
  "reports/numeric-keyword-synergies.json",
  JSON.stringify(report, null, 2),
);
console.log(JSON.stringify(report, null, 2));
